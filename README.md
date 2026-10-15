# EKS deployment playbook

How I deploy services onto EKS: scale-to-zero behind Traefik + KEDA, one manifest per service,
self-contained GitLab pipelines, images built small and non-root.

Written from a real migration of ~25 services (three product lines, dev + UAT) off Docker
Swarm VMs. Every file here is a working template, not a sketch. Placeholders are in
`<ANGLE_BRACKETS>`.

## The shape of it

```
Internet → NLB → Traefik (IngressRoute + basic auth + strip prefix + Host rewrite)
                    ↓
                 KEDA HTTP interceptor  ──wakes──→  Deployment 0→1
                    ↓
                 <svc>-backend (ClusterIP) → pod
```

Every service gets **two Services**:

| Name | Type | Purpose |
|---|---|---|
| `<svc>-backend` | ClusterIP | what KEDA scales toward; callers never use it |
| `<svc>` | ExternalName | DNS alias to the interceptor, so any in-cluster call wakes the pod |

Callers always use port **8080** — the interceptor's, never the app's.

## Folders

| | |
|---|---|
| `01-cluster/` | Karpenter node pools, taints, scale-to-zero, root volume sizing |
| `02-ingress/` | Traefik + KEDA routing, the two-Service idiom, path prefixes |
| `03-service/` | the per-service manifest and its companions (migrate Job, Redis, PVC, weights) |
| `04-pipeline/` | self-contained `.gitlab-ci.yml` templates + the CI RBAC the deployer needs |
| `05-dockerfiles/` | image patterns: FastAPI, Django, ML-with-CPU-torch, Angular SPA |
| `06-multi-env/` | running dev and UAT side by side in one namespace |
| `CHECKLIST.md` | what to do before and after every deploy |
| `LESSONS.md` | the traps, each one learned the expensive way |

## Read this before anything else

**A green deploy job does not mean the service works.** KEDA holds the pod at zero, so the
image is never executed until the first real request. `kubectl rollout status` returns success
against a Deployment scaled to 0 without pulling the image. I shipped broken images twice
because the pipeline was green.

Always wake the service and look:

```bash
kubectl -n <NAMESPACE> run wake --rm -i --restart=Never --image=curlimages/curl -- \
  curl -sS -o /dev/null -w '%{http_code} in %{time_total}s\n' -m 900 \
  http://<svc>.<NAMESPACE>.svc.cluster.local:8080/health
```

## Versions this was proven on
| Component | Version |
|---|---|
| EKS | <x.yy> |
| Karpenter | <x.y.z> |
| Traefik | <x.y.z> |
| KEDA + HTTP add-on | <x.y.z> / <x.y.z> |

The KEDA HTTP interceptor's behaviour is version-sensitive — re-check LESSONS.md against release notes before reusing on newer versions.
