# Checklist

## Before writing anything

- [ ] Read the **whole** upstream Dockerfile and every requirements file.
- [ ] Find the real entrypoint. `EXPOSE` lies; `docker-entrypoint.sh` does not.
- [ ] Grep the code for every env var it reads, and for hardcoded URLs, IPs and credentials.
- [ ] Find what the app needs that is **not** in the repo — model weights, data files,
      `credentials.json` from an archive. These are what block you on deploy day.
- [ ] Check which branch is actually deployed today. It is often not the one you were told.

## Image

- [ ] Non-root uid 1000, port 8080, `WORKDIR` chowned.
- [ ] No credentials, no `.git`, no data directories — `.dockerignore` exists.
- [ ] Dependencies actually installed (not inherited from a mutable base tag).
- [ ] OTel distro + exporter + instrumentor present; `--workers 1`.
- [ ] Build it locally and **run it** before pushing.

## Manifest

- [ ] `envsubst` with an explicit variable allowlist.
- [ ] Secret ref required, not optional.
- [ ] Probe path correct — including the route prefix if you do not strip it.
- [ ] `failureThreshold × periodSeconds` > worst cold start.
- [ ] `kubectl apply --dry-run=server` clean.

## Pipeline

- [ ] `unset AWS_*` then assert the caller identity.
- [ ] Cluster name is a literal.
- [ ] Immutable image tag for the deploy.
- [ ] `retry` includes `script_failure`.
- [ ] `rollout status` only on always-on workloads.

## After deploying — the part people skip

- [ ] **Wake the service** and record the status code and cold-start time.
- [ ] Check it externally: `401` is good, `404` means the route is broken.
- [ ] Confirm traces arrive in APM under the expected service name.
- [ ] Verify identity from inside the pod if it uses cloud APIs.
- [ ] Exercise one **real** endpoint, not just health — health often skips the broken part.
- [ ] Check config actually resolved: `kubectl exec <pod> -- env | grep <KEY>`.

## When something is wrong

| Symptom | Look at |
|---|---|
| 404 externally | basicAuth Secret in the middleware's namespace; IngressRoute target |
| Request hangs then `000` | pod never became Ready — interceptor waited; check the pod |
| Pod Running but never Ready | probe path, probably missing the route prefix |
| CrashLoopBackOff on first wake | the image — it was never executed before this |
| Works, but no traces | `opentelemetry-distro` missing, or workers > 1 |
| Empty results, no error | config fell back to a default — check which store it is reading |
