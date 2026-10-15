# Lessons

Each of these cost real time. Roughly ordered by how much.

## Green CI proves nothing about the image

A scale-to-zero service is never executed by its deploy. `rollout status` passes against a
Deployment at 0 replicas without pulling the image. I shipped two broken images this way — one
missing `opentelemetry-instrument` entirely, CrashLoopBackOff on first wake, job green.

The failure shape is nasty: the KEDA interceptor holds the request open waiting for a pod that
never becomes Ready, so the caller sees a **long hang ending in `000`**, not an error. It reads
as "slow", not "broken".

**Always wake it.** Build the sweep into your process, not your intentions.

## Verify from inside the pod, not from the manifest

The manifest is what you asked for; `kubectl exec <pod> -- env` is what you got. `env:` entries
override `envFrom:`, so a leftover `secretKeyRef` quietly beats the Secret you just created. I
had a service running against the wrong Azure resource while holding the right keys.

## Health endpoints hide the broken part

`/health` that touches no dependency tells you the process is up and nothing else. One service
returned a healthy `/health` for days while every real call 500'd inside the OTel
instrumentation. Another would have returned cheerful results from an **empty** dataset because
a missing env var silently fell back to a local SQLite file.

Exercise a real endpoint. Check row counts.

## My own test harness lied to me

I ran gunicorn with `--daemon` to test the console span exporter, grepped the log file, saw
zero spans, and nearly reported my own fix as a failure. `--daemon` detaches stdout. Re-running
it as a normal container showed the spans immediately.

When a verification disagrees with a solid diagnosis, suspect the harness first.

## A diagnosis that fits all the symptoms can still be wrong

Django traces were missing. Theory 1: Django. Theory 2: `runserver`. Theory 3: gunicorn forking
and killing the SDK thread. All plausible, all wrong. The cause was a **missing package** —
`opentelemetry-distro`, which is what actually configures the exporter. Instrumentors loaded,
`PYTHONPATH` correct, post_fork hook firing, requests served, zero spans.

What settled it was a control: driving traffic at a service known to work, through the same
pipeline, in the same window. 90 spans there, 0 here. That ruled out the pipeline in one shot
and pointed at the image.

## Read the callee, not just the caller

I fixed a URL in a ConfigMap by reading how the caller used it — then had to fix it again,
because the service I pointed it at did not have that route at all. Reading the caller gets you
the shape of the request. Reading the callee tells you whether it can answer.

## Archives carry credentials

Three separate services fetched an S3 archive at build time, using an **AWS key pair committed
in the Dockerfile**, purely to obtain a `credentials.json` holding an API key. Bake an AWS key
into an image, to fetch a zip, to read a key.

Make the code read the environment first with the file as fallback. The archive, the keys and
the awscli layers all disappear.

## Shared brokers split queues silently

A celery broker URL with no database index always lands on db 0. Point two environments at one
Redis and both workers consume the same queue — tasks execute in the wrong environment, no
error anywhere. The VM's Redis was reachable from the cluster, which made it a trap rather than
a wall: it would have worked.

## Deleting someone else's uncommitted work

`git checkout <branch> -- <paths>` overwrites the working tree without asking. I ran it in a
repo with uncommitted changes and destroyed an edit I had made an hour earlier. Check
`git status` before any checkout that names paths.

## Read-only probes, then write

The schema-vs-migration-history conflict, the empty-table discovery, the model identity — all
answered with read-only queries from a throwaway pod before touching anything. Diagnose fully,
present the options, let the owner choose. Especially for anything irreversible on a shared
database.

## Branch names in URLs age badly

Routes keyed on per-repo branch names (`tenant-e-uat`, `master_tenant-e`, `feature/x`) mean nobody
can derive a URL without a lookup table. One uniform suffix per environment — `/eks`, `/uat` —
and the URL follows from the repo name.
