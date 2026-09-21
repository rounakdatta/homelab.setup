#!/usr/bin/env python3
"""Record and verify the provenance of vendored Helm charts.

Charts under kubernetes/**/charts/ are build artifacts pulled from an OCI
registry or an HTTP chart repo, then committed so a deploy reads the tree
instead of the network. That vendoring is deliberate: when the bjw-s chart
repo started 404ing, one unfetchable chart broke every deploy.

What vendoring leaves open is tampering -- a chart edited in place no longer
matches what upstream published, and nothing says so. This records a content
hash per chart and checks it, which catches that **offline**. It deliberately
does not re-pull from upstream: that would put 13 third-party hosts back in
the path of a green build, to detect drift that cannot affect us anyway,
since the vendored copy is what deploys.

No third-party imports on purpose -- this has to run on a bare python3, in CI
and on any machine, without a pip install standing between you and a check.

  charts-lock.py --write    regenerate kubernetes/charts.lock
  charts-lock.py --check    verify the tree against it (exit 1 on mismatch)
"""

import argparse
import hashlib
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
KUBE_DIR = REPO_ROOT / "kubernetes"
LOCK_PATH = KUBE_DIR / "charts.lock"
FIELDS = ("path", "chart", "version", "repo", "sha256")

HEADER = """\
# Provenance for the vendored Helm charts under kubernetes/**/charts/.
#
# GENERATED -- do not edit by hand. Regenerate with:
#   python3 .github/scripts/charts-lock.py --write
#
# `sha256` is a content hash of the vendored directory, not an upstream
# digest: it answers "has this tree been altered since it was vendored?",
# which is checkable without talking to any upstream. `repo` and `version`
# come from the sibling kustomization.yaml and say where it came from.
"""


def parse_block_seq(text, key):
    """Entries of a top-level `key:` list whose items are flat `k: v` maps.

    Enough for kustomize's helmCharts and for the lock this script writes;
    not a YAML parser, and not trying to be one.
    """
    lines = text.splitlines()
    entries, indent, inside = [], None, False

    for raw in lines:
        stripped = raw.strip()
        if not inside:
            if stripped == f"{key}:":
                inside = True
            continue

        if not stripped or stripped.startswith("#"):
            continue

        cur = len(raw) - len(raw.lstrip())
        item = stripped.startswith("- ")

        if indent is None and item:
            indent = cur
        # Dedent past the list, or a new top-level key, ends the block.
        if indent is not None and cur < indent:
            break
        if not item and cur <= indent:
            break

        body = stripped[2:].strip() if item else stripped
        if item:
            entries.append({})
        if ":" not in body or not entries:
            continue
        k, _, v = body.partition(":")
        v = v.strip().strip('"').strip("'")
        entries[-1][k.strip()] = v

    return entries


def chart_dirs():
    """Every vendored chart directory, with the kustomization that owns it."""
    for charts in sorted(KUBE_DIR.glob("**/charts")):
        if not charts.is_dir():
            continue
        # Only a charts/ dir beside a kustomization.yaml is a vendoring
        # location. Helm subcharts live in <chart>/charts/ too, and those
        # are part of their parent's contents, not separate entries.
        kustomization = charts.parent / "kustomization.yaml"
        if not kustomization.exists():
            continue
        for chart in sorted(p for p in charts.iterdir() if p.is_dir()):
            yield chart, kustomization


def content_hash(chart_dir):
    """Deterministic hash over every file's path and contents."""
    digest = hashlib.sha256()
    for path in sorted(p for p in chart_dir.rglob("*") if p.is_file()):
        digest.update(path.relative_to(chart_dir).as_posix().encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
        digest.update(b"\0")
    return digest.hexdigest()


def helm_source(kustomization, chart_name):
    """The repo/version the kustomization declares for this chart."""
    if not kustomization.exists():
        return {}
    for entry in parse_block_seq(kustomization.read_text(), "helmCharts"):
        if entry.get("name") == chart_name:
            return {"repo": entry.get("repo", ""), "version": entry.get("version", "")}
    return {}


def build():
    entries = []
    for chart_dir, kustomization in chart_dirs():
        # Directories are named "<chart>-<version>" and hold one inner
        # directory named for the chart itself; that is what kustomize
        # calls it, so prefer it over splitting the outer name.
        inner = [p for p in chart_dir.iterdir() if p.is_dir()]
        chart_name = inner[0].name if len(inner) == 1 else chart_dir.name
        src = helm_source(kustomization, chart_name)
        entries.append(
            {
                "path": chart_dir.relative_to(REPO_ROOT).as_posix(),
                "chart": chart_name,
                "version": src.get("version", ""),
                "repo": src.get("repo", ""),
                "sha256": content_hash(chart_dir),
            }
        )
    return entries


def render(entries):
    out = [HEADER, "charts:"]
    for e in entries:
        out.append(f"  - path: {e['path']}")
        out.extend(f"    {f}: {e[f]}" for f in FIELDS[1:])
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="regenerate the lock")
    mode.add_argument("--check", action="store_true", help="verify against it")
    args = ap.parse_args()

    entries = build()
    rel_lock = LOCK_PATH.relative_to(REPO_ROOT)

    if args.write:
        LOCK_PATH.write_text(render(entries))
        print(f"wrote {rel_lock} ({len(entries)} charts)")
        return 0

    if not LOCK_PATH.exists():
        print(f"ERROR: {rel_lock} is missing.")
        print("Run: python3 .github/scripts/charts-lock.py --write")
        return 1

    locked = {e["path"]: e for e in parse_block_seq(LOCK_PATH.read_text(), "charts")}
    found = {e["path"]: e for e in entries}
    problems = []

    for path in sorted(set(locked) | set(found)):
        want, have = locked.get(path), found.get(path)
        if want is None:
            problems.append(f"  + {path}\n      vendored but not in the lock")
        elif have is None:
            problems.append(f"  - {path}\n      in the lock but not vendored")
        elif want.get("sha256") != have.get("sha256"):
            problems.append(
                f"  ! {path}\n"
                f"      contents changed since it was vendored\n"
                f"      lock: {want.get('sha256')}\n"
                f"      tree: {have.get('sha256')}"
            )

    if problems:
        print(f"Vendored charts do not match {rel_lock}:\n")
        print("\n".join(problems))
        print(
            "\nA vendored chart is an upstream artifact and is not edited in place.\n"
            "If you bumped a chart version, re-render and refresh the lock:\n"
            "  kustomize build --enable-helm kubernetes/ >/dev/null\n"
            "  python3 .github/scripts/charts-lock.py --write\n"
            "If you changed no chart, something altered one -- check the diff."
        )
        return 1

    print(f"{rel_lock} OK ({len(found)} charts match)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
