#!/usr/bin/env python3
"""
Pre-apply migration helper for the deploy-stuff workflow.

Some Kubernetes fields are immutable after creation. When a resource's
manifest changes one of these fields — typically when switching from a
hand-rolled manifest to a Helm-chart-rendered one — `kubectl apply` errors
out with `field is immutable`. This script reads the rendered kustomize
output, looks up each watched resource's live state, and deletes any whose
immutable fields would conflict, letting the subsequent `kubectl apply`
recreate them cleanly.

Watched immutable fields:
- Deployment / StatefulSet / DaemonSet:   spec.selector.matchLabels
- ClusterRoleBinding / RoleBinding:       roleRef

Idempotent: once each resource matches the manifest, this is a no-op.

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

WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet"}
ROLEBINDING_KINDS = {"ClusterRoleBinding", "RoleBinding"}


def kubectl_get(kind: str, name: str, namespace: str | None) -> dict | None:
    cmd = ["kubectl", "get", kind.lower(), name, "-o", "json"]
    if namespace:
        cmd = ["kubectl", "-n", namespace, "get", kind.lower(), name, "-o", "json"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout)


def kubectl_delete(kind: str, name: str, namespace: str | None) -> None:
    cmd = ["kubectl", "delete", kind.lower(), name, "--wait=true"]
    if namespace:
        cmd = ["kubectl", "-n", namespace, "delete", kind.lower(), name, "--wait=true"]
    subprocess.run(cmd, check=True)


def check_workload(d: dict) -> tuple[str, str, str] | None:
    """Return (kind, ns, name) if this workload needs migration, else None."""
    kind = d["kind"]
    md = d.get("metadata") or {}
    name = md.get("name")
    ns = md.get("namespace")
    if not name or not ns:
        return None
    new_sel = (d.get("spec") or {}).get("selector", {}).get("matchLabels")
    if not new_sel:
        return None

    live = kubectl_get(kind, name, ns)
    if live is None:
        return None
    live_sel = live.get("spec", {}).get("selector", {}).get("matchLabels", {})
    if live_sel == new_sel:
        return None

    print(
        f"Migrating {kind}/{ns}/{name}: live selector {live_sel} "
        f"would conflict with manifest selector {new_sel} (immutable). Deleting.",
        flush=True,
    )
    return kind, ns, name


def check_rolebinding(d: dict) -> tuple[str, str | None, str] | None:
    """Return (kind, ns, name) if this binding needs migration, else None.

    ClusterRoleBindings are cluster-scoped (ns=None); RoleBindings are namespaced.
    """
    kind = d["kind"]
    md = d.get("metadata") or {}
    name = md.get("name")
    ns = md.get("namespace") if kind == "RoleBinding" else None
    if not name:
        return None
    if kind == "RoleBinding" and not ns:
        return None
    new_ref = d.get("roleRef")
    if not new_ref:
        return None

    live = kubectl_get(kind, name, ns)
    if live is None:
        return None
    live_ref = live.get("roleRef", {})

    # Compare the immutable subset (apiGroup/kind/name); subjects can change freely.
    keys = ("apiGroup", "kind", "name")
    if all(live_ref.get(k) == new_ref.get(k) for k in keys):
        return None

    where = f"{ns}/{name}" if ns else name
    print(
        f"Migrating {kind}/{where}: live roleRef {live_ref} "
        f"would conflict with manifest roleRef {new_ref} (immutable). Deleting.",
        flush=True,
    )
    return kind, ns, name


def main(manifest_path: str) -> None:
    with open(manifest_path) as f:
        docs = list(yaml.safe_load_all(f))

    migrations = 0
    for d in docs:
        if not d:
            continue
        kind = d.get("kind")
        target = None
        if kind in WORKLOAD_KINDS:
            target = check_workload(d)
        elif kind in ROLEBINDING_KINDS:
            target = check_rolebinding(d)
        if target is None:
            continue
        t_kind, t_ns, t_name = target
        kubectl_delete(t_kind, t_name, t_ns)
        migrations += 1

    if migrations == 0:
        print("No immutable-field migrations needed.", flush=True)
    else:
        print(f"Performed {migrations} migration(s).", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: migrate-selectors.py <manifest.yaml>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
