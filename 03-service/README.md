# Per-service manifest

One file per service, rendered with `envsubst` from the pipeline. Everything the service needs
in one place: Deployment, both Services, HTTPScaledObject, Middlewares, IngressRoute.

| File | When you need it |
|---|---|
| `service.yaml` | always — the base template |
| `migrate-job.yaml` | Django/any app with schema migrations |
| `redis.yaml` | celery broker or cache (see below — do not share one) |
| `media-pvc.yaml` | app writes user uploads to disk |
| `weights-loader.yaml` | model weights or data files too big for the image |
| `gunicorn.conf.py` | any Django/WSGI app, for OpenTelemetry to survive the fork |

## Variables

Rendered with an explicit allowlist, never a bare `envsubst` — otherwise it eats `$(...)` in
the manifest, like `http://$(K8S_NODE_IP):4318`.

```bash
envsubst '$SVC_NAME $SVC_IMAGE $SVC_POOL $SVC_PATH $SVC_ENDPOINTS $SVC_SECRET' \
  < kubernetes/<svc>.yaml | kubectl apply -f -
```

## Secrets: required, not optional

```yaml
envFrom:
  - secretRef: { name: ${SVC_SECRET} }     # no `optional: true`
```

If the app raises at import without a key, a **required** ref leaves the pod `Pending` with the
Secret named in the event. Marked `optional: true` it schedules and CrashLoopBackOffs with the
cause buried in a traceback. The first is diagnosable in one `kubectl describe`.

## Probes

Use a real health endpoint if the app has one. If not, `/openapi.json` works for FastAPI — it
proves the ASGI app is up rather than just that the port is bound, and costs no LLM call.
`tcpSocket` only if there is genuinely nothing to hit.

`failureThreshold × periodSeconds` must exceed the worst cold start, including model load.

## Migrations

Never in the entrypoint — every replica races the same migration. Use the Job, and have the
pipeline poll for **both** `Complete` and `Failed`:

```bash
kubectl -n <NAMESPACE> delete job/$SVC_NAME-migrate --ignore-not-found --wait=true
envsubst ... < kubernetes/migrate-job.yaml | kubectl apply -f -
# then poll .status.conditions
```

`wait --for=condition=complete` alone ignores a failed Job and burns the whole timeout, which
reads as a hang. A Job's pod template is immutable, so delete before re-applying.

## Redis: one per service

A celery broker URL built as `redis://$HOST:$PORT` with **no database index** always lands on
db 0. Two environments pointing at the same Redis share that db and split the queue between
them — tasks run in the wrong place with no error anywhere. Give each environment its own.

## Weights and data files

`weights-loader.yaml` primes a node-local hostPath from an S3 archive via an initContainer,
keyed on the object's ETag so only the first pod on a node pays. hostPath, not a PVC: the
archive is identical for every pod and read-only once extracted, and it survives a
0→1→0→1 cycle.

Mount it read-only unless the library needs to write lock files beside the model.
