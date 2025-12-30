# Hugo Sites Framework Implementation Plan

## Goal
Create a reusable framework to host multiple Hugo static sites on the homelab K8s cluster. Adding a new site should require minimal YAML (~10 lines).

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Per-site Deployment                            │
│                                                 │
│  ┌──────────────────┐    ┌──────────────────┐   │
│  │  Init Container  │    │      Nginx       │   │
│  │  - git clone     │───▶│  serves static   │   │
│  │  - hugo build    │    │  files from      │   │
│  │  - copy to vol   │    │  shared volume   │   │
│  └──────────────────┘    └──────────────────┘   │
│           │                       │             │
│           ▼                       ▼             │
│     [emptyDir volume]      [Traefik Ingress]    │
│                                   │             │
│                            [cert-manager TLS]   │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Daily CronJob                                  │
│  - kubectl rollout restart deployment           │
│  - Triggers init container to re-clone/build    │
└─────────────────────────────────────────────────┘
```

## Directory Structure

```
kubernetes/apps/hugo-sites/
├── kustomization.yaml          # Includes base + all site overlays
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml         # Generic deployment template
│   ├── service.yaml
│   ├── ingress.yaml
│   └── cronjob.yaml            # Daily restart trigger
└── sites/
    └── blog/                   # One folder per site
        ├── kustomization.yaml  # Patches base with site-specific values
        └── config.env          # HUGO_REPO, HUGO_BRANCH, HUGO_HOSTNAME
```

## Implementation Steps

### Step 1: Create Base Templates

**base/deployment.yaml**
- Init container: `alpine/git` + `hugomods/hugo` (or custom image)
- Main container: `nginx:alpine`
- Environment variables: `HUGO_REPO`, `HUGO_BRANCH`
- Shared emptyDir volume for built files

**base/service.yaml**
- ClusterIP service on port 80

**base/ingress.yaml**
- Traefik IngressRoute or standard Ingress
- TLS via cert-manager (letsencrypt-prod)
- Hostname from `HUGO_HOSTNAME`

**base/cronjob.yaml**
- Runs daily at 4 AM (after backups)
- Executes: `kubectl rollout restart deployment/<site-name>`
- Uses ServiceAccount with limited RBAC

### Step 2: Create Site Overlay (blog example)

**sites/blog/kustomization.yaml**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namePrefix: blog-

configMapGenerator:
  - name: hugo-config
    literals:
      - HUGO_REPO=https://github.com/rounakdatta/rounakdatta.github.io
      - HUGO_BRANCH=2025

patches:
  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: blog.taptappers.club
    target:
      kind: Ingress
```

### Step 3: RBAC for CronJob

- ServiceAccount: `hugo-deployer`
- Role: Can restart deployments in `apps` namespace
- RoleBinding: Binds ServiceAccount to Role

### Step 4: Add to Main Kustomization

Update `kubernetes/apps/kustomization.yaml` to include:
```yaml
resources:
  - hugo-sites/
```

## Files to Create

| File | Purpose |
|------|---------|
| `kubernetes/apps/hugo-sites/kustomization.yaml` | Main kustomization |
| `kubernetes/apps/hugo-sites/base/kustomization.yaml` | Base resources |
| `kubernetes/apps/hugo-sites/base/deployment.yaml` | Generic deployment |
| `kubernetes/apps/hugo-sites/base/service.yaml` | Service template |
| `kubernetes/apps/hugo-sites/base/ingress.yaml` | Ingress template |
| `kubernetes/apps/hugo-sites/base/cronjob.yaml` | Daily restart job |
| `kubernetes/apps/hugo-sites/base/rbac.yaml` | ServiceAccount + Role |
| `kubernetes/apps/hugo-sites/sites/blog/kustomization.yaml` | Blog site overlay |

## Adding a New Site

To add a new Hugo site, create:
```
kubernetes/apps/hugo-sites/sites/<site-name>/kustomization.yaml
```

With content:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namePrefix: <site-name>-

configMapGenerator:
  - name: hugo-config
    literals:
      - HUGO_REPO=https://github.com/<user>/<repo>
      - HUGO_BRANCH=<branch>

patches:
  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: <hostname>
    target:
      kind: Ingress
```

Then add to `kubernetes/apps/hugo-sites/kustomization.yaml`:
```yaml
resources:
  - sites/<site-name>
```

## Questions Before Implementation

1. What hostname for the first site? (e.g., `blog.taptappers.club`)
2. Should sites be in `apps` namespace or a new `sites` namespace?
3. Do you need Authelia protection on any of these sites, or all public?
