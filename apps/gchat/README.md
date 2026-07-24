# gchat scaling dashboard

Deploys the gchat scaling dashboard from `gimages.azurecr.io` at
`https://gchat.gerardosalazar.com`.

## Prerequisites

- The `apps` namespace and `acr-secret` image pull secret exist (created by
  `terraform/apps` when ACR credentials are configured).
- The image has been pushed to ACR:
  `gimages.azurecr.io/gchat-scaling-dashboard:1.0`
- DNS for `gchat.gerardosalazar.com` points at the cluster load balancer (via the
  `gchat` CNAME in `terraform/infra/cloudflare.tf`).

## Deploy

From the gnode repo root:

```bash
kubectl apply -f apps/gchat/deployment.yaml
kubectl apply -f apps/gchat/ingress.yaml
```

Or apply both at once:

```bash
kubectl apply -f apps/gchat/
```

cert-manager provisions the TLS certificate automatically via the
`letsencrypt-prod` ClusterIssuer.

## Verify

```bash
kubectl -n apps get deployment/gchat-scaling-dashboard
kubectl -n apps get service/gchat-scaling-dashboard
kubectl -n apps get ingress/gchat
kubectl -n apps rollout status deployment/gchat-scaling-dashboard
```

Then open `https://gchat.gerardosalazar.com`.
