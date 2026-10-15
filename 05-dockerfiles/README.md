# Image patterns

Four templates, all: multi-stage where it helps, non-root uid 1000, port 8080, no credentials.

| File | For |
|---|---|
| `python-fastapi.Dockerfile` | plain Python API |
| `python-ml-cpu-torch.Dockerfile` | anything pulling torch / sentence-transformers |
| `python-django.Dockerfile` | Django + celery, with playwright/cairo system deps |
| `node-angular-spa.Dockerfile` | SPA built then served by nginx-unprivileged |
| `nginx-spa-default.conf.template` | SPA nginx config with env-substituted upstreams |

## Port 8080, not 80

uid 1000 cannot bind a privileged port under the kubelet. It *works* under Docker, which sets
`net.ipv4.ip_unprivileged_port_start=0`, so the image looks fine locally and fails only in the
cluster. Keep `EXPOSE`, the entrypoint and `containerPort` in step.

## chown the WORKDIR itself

```dockerfile
RUN mkdir -p /app && chown 1000:1000 /app
WORKDIR /app
COPY --chown=1000:1000 . .
```

Docker creates `WORKDIR` **root-owned**, and `--chown` on the `COPY` covers only the copied
files. Anything resolving a relative path at runtime — `os.makedirs("data")` — then fails as
uid 1000, at startup, in an image that otherwise looks correct.

## CPU torch

```dockerfile
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch && \
    pip install -r requirements.txt
```

Install it **first**, so the resolver finds torch already satisfied. The default PyPI wheel
bundles the CUDA stack — nvidia-cudnn alone is 553 MB — for a workload that never sees a GPU.
196 MB versus ~2 GB.

## Two pip installs when resolvers fight

If one dependency tree constrains `protobuf`/`googleapis-common-protos` and another constrains
them differently, pip backtracks through hundreds of versions at ~20s each and may never
finish. Split into two `pip install` steps so neither has to satisfy the other.

## Things to check in an inherited Dockerfile

- **Two `FROM` lines where nothing is copied from the first.** The real base is the second one,
  often a mutable registry tag — so `requirements.txt` edits change nothing and the same commit
  resolves differently on different days.
- **`pip install -r requirements.txt` commented out.** Same cause.
- **Commented-out AWS keys.** Commenting removes them from the build, not from git history.
- **`psycopg2` instead of `psycopg2-binary`.** The source package needs `pg_config`.
- **`--reload` in the entrypoint.** Dev server flag; also multiplies memory by worker count.
- **A base image on an EOL distro.** `apt-get update` still succeeds — the indexes are
  published — then `apt-get install` 404s on the pool. Reads as a flaky mirror, is not.

## OpenTelemetry

Three packages, and **`opentelemetry-distro` is the one that matters**:

```
opentelemetry-distro
opentelemetry-exporter-otlp-proto-http
opentelemetry-instrumentation-<framework>
```

`opentelemetry-instrument` only loads instrumentors. The *distro* is what reads
`OTEL_TRACES_EXPORTER` and installs the exporter and span processor. Without it spans are
created and dropped, silently.

**`--workers 1`.** The SDK initialises in the parent and forked children never re-initialise
it, so anything above 1 emits zero spans while serving normally. Scale on replicas instead.
gunicorn forks even with `--workers 1`, so it additionally needs the `post_fork` hook in
`../03-service/gunicorn.conf.py`.
