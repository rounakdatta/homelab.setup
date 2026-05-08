#!/usr/bin/env python3
"""
Pre-apply selector migration helper for the deploy-stuff workflow.

`spec.selector` on Deployment/StatefulSet/DaemonSet is immutable. Whenever a
workload's selector changes — typically when switching from a hand-rolled
manifest to a Helm-chart-rendered one — `kubectl apply` errors out with
`field is immutable`.

This script reads the rendered kustomize output, looks up each workload's
live selector, and deletes any whose selector would conflict with the new
one. Idempotent: once selectors match, it's a no-op.

Usage:
    kubectl kustomize --enable-helm kubernetes/ > manifest.yaml
    python3 .github/scripts/migrate-selectors.py manifest.yaml
    kubectl apply -f manifest.yaml
"""

from __future__ import annotations

import json
import subprocess
import sys

import yaml

WATCHED_KINDS = {"Deployment", "StatefulSet", "DaemonSet"}


def get_live_selector(kind: str, namespace: str, name: str) -> dict | None:
    proc = subprocess.run(
        ["kubectl", "-n", namespace, "get", kind.lower(), name, "-o", "json"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout).get("spec", {}).get("selector", {}).get("matchLabels", {})


def delete(kind: str, namespace: str, name: str) -> None:
    subprocess.run(
        ["kubectl", "-n", namespace, "delete", kind.lower(), name, "--wait=true"],
        check=True,
    )


def main(manifest_path: str) -> None:
    with open(manifest_path) as f:
        docs = list(yaml.safe_load_all(f))

    migrations = 0
    for d in docs:
        if not d:
            continue
        kind = d.get("kind")
        if kind not in WATCHED_KINDS:
            continue
        md = d.get("metadata") or {}
        name = md.get("name")
        ns = md.get("namespace")
        if not name or not ns:
            continue
        new_sel = (d.get("spec") or {}).get("selector", {}).get("matchLabels")
        if not new_sel:
            continue

        live_sel = get_live_selector(kind, ns, name)
        if live_sel is None:
            continue  # doesn't exist yet — kubectl apply will create it
        if live_sel == new_sel:
            continue  # already migrated, no-op

        print(
            f"Migrating {kind}/{ns}/{name}: live selector {live_sel} "
            f"would conflict with manifest selector {new_sel} (immutable). Deleting.",
            flush=True,
        )
        delete(kind, ns, name)
        migrations += 1

    if migrations == 0:
        print("No selector migrations needed.", flush=True)
    else:
        print(f"Performed {migrations} migration(s).", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: migrate-selectors.py <manifest.yaml>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
