# Cluster and node pools

## Karpenter node pools

One pool per tenant, taint + nodeSelector so workloads land where you intend. `nodepool.yaml`
is a working example: spot CPU pool, 200Gi gp3 root.

Key choices and why:

- **Spot, with `retry` in CI.** A reclaim kills a build pod and the docker CLI exits 1, which
  GitLab records as `script_failure` — a retry list without that value never fires.
- **200Gi root, not Karpenter's 20Gi default.** Anything that extracts a multi-GB model
  archive onto the node fills the default disk and the pod goes `Evicted` with a confusing
  message. Size for the largest archive you prime, not the image.
- **`consolidateAfter` longer than your `scaledownPeriod`.** Otherwise Karpenter removes the
  node while KEDA still thinks a pod might come back, and every wake pays a node boot.
- **Taint the pool.** `workload=<POOL>:NoSchedule` plus a matching toleration keeps other
  namespaces off your nodes without needing a separate cluster.

## Scale to zero

KEDA HTTP add-on. Per service:

```yaml
replicas: { min: 0, max: 2 }
scaledownPeriod: 1800      # seconds of no traffic before going back to 0
```

Pick `scaledownPeriod` from what a cold start actually costs:

| Cold start | Suggested |
|---|---|
| small API, image cached | 600–1800 |
| multi-GB model load or archive prime | 3600 |

Measure it rather than guessing — a Python web service on a warm node here was consistently
~6s, and the number that matters is node boot + image pull + model load, not the app.

**The HPA will show `MINPODS 1` even when you set `min: 0`.** Kubernetes HPAs cannot have
`minReplicas: 0`, so KEDA always creates it with 1 and does the 1→0 step itself from its own
controller. Check `REPLICAS`, not `MINPODS`.

## IRSA

Give pods a ServiceAccount bound to an IAM role; never static keys. Verify from inside a pod:

```bash
kubectl -n <NAMESPACE> exec <pod> -- python3 -c \
  "import boto3; print(boto3.client('sts').get_caller_identity()['Arn'])"
```

You want to see `assumed-role/<your-irsa-role>`. If application code passes
`aws_access_key_id=` explicitly it will defeat IRSA — see `LESSONS.md`.
