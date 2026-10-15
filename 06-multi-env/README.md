# Dev and UAT in one namespace

Same cluster, same namespace, `-uat` suffix on every object, `/<repo>/uat` on every route.
Dev keeps `/eks`.

Why not a second namespace: you would duplicate IRSA, RBAC, the weights loader, the auth
middleware and the ingress wiring, for isolation the suffix already gives you.

## One manifest, two environments

The manifest takes the config source as variables; the pipeline supplies them:

```yaml
.deploy:
  variables:
    SVC_ENDPOINTS: <SHARED_CONFIGMAP>
    SVC_SECRET: <svc>-secret

deploy:uat:
  extends: .deploy
  variables:
    SVC_NAME: <svc>-uat
    SVC_PATH: /<repo>/uat
    SVC_ENDPOINTS: <SHARED_CONFIGMAP>-uat
    SVC_SECRET: <svc>-uat-secret
```

## Rules that keep the two apart

- **Separate Secrets and ConfigMap.** Sharing them means UAT writes to dev's database.
- **The UAT ConfigMap must point at UAT peers.** If `SERVICE_A_URL` still resolves to the dev
  Service, UAT traffic silently flows into dev.
- **Separate Redis** per environment — see `../03-service/README.md`.
- **Scheduler singletons stay at `replicas: 0`** in the second environment while the first is
  still running, if both read their schedule from the same database. Two celery beats on one
  DB fire every periodic task twice, and some of those send real email.
- **Per-environment hostPath** for weights if the archives differ.

## Branching

Cut one uniformly named branch (`eks-uat`) from whatever ref each repo actually uses for that
environment, and record the mapping in one table. Twelve repos with twelve different branch
names is not something anyone will remember.

Add it to `workflow.rules` so pipelines run there:

```yaml
workflow:
  rules:
    - if: '$CI_COMMIT_BRANCH == "eks"'
    - if: '$CI_COMMIT_BRANCH == "eks-uat"'
```

**The second environment's branch is different code**, not a rebase. Every fix made on the
first branch has to be re-derived there — different requirements, different hardcoded paths,
sometimes a different LLM provider. Copying the deployment files alone gives you pods that
start and fail.
