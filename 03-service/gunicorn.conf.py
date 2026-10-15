"""gunicorn configuration — exists solely to make OpenTelemetry work.

`opentelemetry-instrument` sets PYTHONPATH to its auto_instrumentation directory and lets
Python's `sitecustomize` hook build the tracer provider at INTERPRETER STARTUP. gunicorn then
`fork()`s its workers: a fork is not a new interpreter, so sitecustomize never runs again, and
the child inherits a provider whose BatchSpanProcessor export thread did not survive the fork.
The app serves normally and emits nothing — which is exactly what install-log C37 describes on
Django, and the same mechanism C36 measured on uvicorn --workers 2.

Re-importing sitecustomize in post_fork rebuilds the SDK inside each worker. This is the
documented gunicorn pattern; --workers 1 does NOT avoid it, because gunicorn forks a worker
even for one.
"""


def post_fork(server, worker):
    from opentelemetry.instrumentation.auto_instrumentation import (  # noqa: F401
        sitecustomize,
    )

    server.log.info("opentelemetry re-initialised in worker %s", worker.pid)
