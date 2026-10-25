# Kubernetes delivery

The `apisix` chart is consumed as published (chart 2.18.2, APISIX 3.19.0);
nothing from apache/apisix-helm-chart is vendored. `values.yaml` is the shared,
HelmRelease-ready values file; secrets are created separately.

Kubernetes runs the stock `apache/apisix:3.19.0-debian` image, which already
embeds the dashboard. The fork's own image (`docker/debian-dev/Dockerfile`,
built by `deploy/docker/`) is not pushed to a registry yet; once it is, set
`image.repository` and `image.tag` in `values.yaml`.

## Local OrbStack Kubernetes

```bash
kubectl create namespace ai-gateway
kubectl label namespace ai-gateway pod-security.kubernetes.io/enforce=restricted
kubectl -n ai-gateway create secret generic apisix-admin \
  --from-literal=admin="$(openssl rand -hex 16)" --from-literal=viewer="$(openssl rand -hex 16)"
kubectl -n ai-gateway create secret generic apisix-etcd --from-literal=etcd-root-password="$(openssl rand -hex 16)"
kubectl -n ai-gateway create secret generic apisix-provider-keys \
  --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY"   # add the others you have
kubectl kustomize --enable-helm --load-restrictor LoadRestrictionsNone \
  deploy/kubernetes/orbstack | kubectl apply -f -
```

kustomize inflates the chart (`orbstack/kustomization.yaml`) and applies the
same patch as the Flux `postRenderers` block: the chart's `wait-etcd` init
container carries no securityContext, and a `restricted` namespace rejects the
pod without it. Helm 4 no longer runs script post-renderers, hence kustomize.

Then `kubectl -n ai-gateway get svc apisix-gateway` for the LoadBalancer IP
(port 80), and `kubectl -n ai-gateway port-forward svc/apisix-admin 9180` for
the Admin API and dashboard at http://localhost:9180/ui/. etcd runs with RBAC
and a NetworkPolicy that admits only APISIX pods.

## home-cluster (Talos + Flux + makejinja)

`home-cluster/` is a ready-to-copy app directory in that repo's `.j2` shape
(delimiters `#{ }#` / `#% %#`, `${SECRET_DOMAIN}` left for Flux, one Secret per
`*.sops.yaml` file). Nothing has been committed into `~/dev/home-cluster`;
`home-cluster/HANDOVER.md` lists the copy steps and the `cluster.toml`,
validator and docs edits that repo requires for a new gated app.
