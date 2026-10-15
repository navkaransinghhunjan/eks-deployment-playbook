# Pipeline

Self-contained `.gitlab-ci.yml` per repo — no `include:` of shared templates. Each repo owns
its build and deploy, so a change to one cannot break the others.

| File | For |
|---|---|
| `gitlab-ci.service.yml` | a plain service: build → deploy |
| `gitlab-ci.django-service.yml` | adds PVC, migrate Job, worker/beat rollouts, Redis |
| `ci-rbac.yaml` | the Role the CI deployer needs in the target namespace |

## Stages

`test` (allow_failure) → `build` (manual) → `deploy` (manual).

Manual on purpose: these deploy to a shared cluster, and an accidental push should not roll
something out.

## Three image tags

| Tag | Mutable | Purpose |
|---|---|---|
| `$CI_COMMIT_REF_SLUG-$CI_COMMIT_SHORT_SHA` | no | what gets deployed |
| `$CI_COMMIT_REF_SLUG` | yes | this branch's last build, first `--cache-from` |
| `cache` | yes | shared, so a new branch starts warm |

**Never deploy a mutable tag.** `kubectl apply` with an unchanged image string is a no-op — no
new ReplicaSet, and `rollout status` passes instantly against the *old* pods.

Because the deployed tag contains the SHA, **a deploy needs a build on that same commit**. A
manifest-only change still needs a rebuild, or the deploy references a tag that does not exist.

## Credentials

```yaml
before_script:
  - unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
  - aws sts get-caller-identity
  - |
    aws sts get-caller-identity --query Arn --output text \
      | grep -q '<CI_IRSA_ROLE>' || { echo "FATAL - wrong identity"; exit 1; }
```

A CI variable holding someone's static key silently overrides the job pod's IRSA. That cost me
a half-applied deploy: the human's key carried an admin policy that covers **no custom
resources**, so Deployment and Service applied and every `traefik.io` / `http.keda.sh` object
403'd. Unset first, then assert the identity before touching the cluster.

**The cluster name is a literal, never a CI variable.** A group variable once redirected a
non-prod deploy at the wrong cluster.

## No rollout status on a scale-to-zero service

```yaml
- kubectl -n <NAMESPACE> get deploy/$SVC_NAME svc/$SVC_NAME httpscaledobject.http.keda.sh/$SVC_NAME
- echo "deployed — held at 0 by KEDA; wake it before believing it"
```

Do run `rollout status` on things that are always on — workers, beat, Redis. A failure there
is real.

## Spot runners

```yaml
retry:
  max: 2
  when: [script_failure, runner_system_failure, stuck_or_timeout_failure]
```

`script_failure` is the one people leave out, and it is the one that matters: a spot reclaim
kills dind, the docker CLI exits 1, and GitLab records a *script* failure.

## RBAC

`ci-rbac.yaml` is the Role in the target namespace. Add verbs as you hit them — each 403 is a
genuine permission the deployer had not needed before (`persistentvolumeclaims`, `batch/jobs`,
`endpoints` all arrived that way). Note it has no `delete` on PVCs, deliberately.
