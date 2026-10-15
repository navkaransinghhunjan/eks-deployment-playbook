# Ingress

Traefik IngressRoute → KEDA interceptor → your pod. `../03-service/service.yaml` contains the
full set; this explains the parts.

## The four pieces

```yaml
middlewares:
  - { name: <BASIC_AUTH_MIDDLEWARE> }   # auth
  - { name: strip-<svc> }               # remove the public prefix
  - { name: host-<svc> }                # rewrite Host so KEDA can match
services:
  - name: keda-add-ons-http-interceptor-proxy
    namespace: keda
    port: 8080
    passHostHeader: true
```

**Match on Host, not path, in the HTTPScaledObject.** Traefik strips the public prefix before
the request reaches the interceptor, so a path match would never see it. That is what the
`host-<svc>` middleware is for — it rewrites `Host` to the in-cluster service name, which the
HTTPScaledObject then matches on.

**Never point an IngressRoute at an ExternalName Service.** Traefik rejects those and silently
drops the route. The 404 is byte-identical to the interceptor's own 404, so you will debug the
wrong thing. Always target the interceptor directly, cross-namespace.

## Two 404s that look the same

| Cause | Tell |
|---|---|
| basicAuth Secret missing from the middleware's namespace | route silently dropped → 404 instead of 401 |
| IngressRoute targeting an ExternalName | Traefik logs it; `kubectl -n traefik logs deploy/traefik \| grep -i externalname` |

A **401 is good news** — it means the route, the middlewares and the interceptor are all wired.

## Path prefixes and SPAs

Convention: `https://<PUBLIC_HOST>/<repo>/<branch>`.

For anything that emits **absolute** asset URLs — Angular, React, Streamlit — stripping the
prefix breaks every asset while `index.html` still returns 200. The page loads blank and reads
as a broken route. Two mutually exclusive options:

1. **Strip the prefix** and tell the app its base path (`<base href>`, `BASE_PATH` as FastAPI
   `root_path`). App serves at `/`, generated URLs carry the prefix.
2. **Do not strip** and set the app's own base-path option (Streamlit
   `--server.baseUrlPath`, Django `FORCE_SCRIPT_NAME`).

Doing both cancels out and 404s everything.

**If you choose option 2, the probes need the prefix too** — the kubelet talks to the container
directly, bypassing Traefik, so `/health` becomes `<SVC_PATH>/health`. Miss this and the pod
runs forever without becoming Ready, which reads as a hang rather than a misconfiguration.
