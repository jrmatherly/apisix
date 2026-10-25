# Hand-over: APISIX app for ~/dev/home-cluster

Nothing here has been copied into or committed to home-cluster. The directory
`template/config/kubernetes/apps/ai-gateway/` mirrors that repo's source-template
tree (makejinja `.j2`, rendered by `just configure` into `kubernetes/apps/`).

## Copy

```bash
cp -R deploy/kubernetes/home-cluster/template/config/kubernetes/apps/ai-gateway \
      ~/dev/home-cluster/template/config/kubernetes/apps/
```

`ai-gateway` is a new namespace, so no existing namespace kustomization needs
editing: `cluster-apps` picks up `kubernetes/apps/ai-gateway/kustomization.yaml`.

## Register the feature gate (four places, per `.claude/rules/validator.md`)

1. `template/scripts/validate.py`: add an `Apisix(Model)` section with
   `admin_key`, `viewer_key`, `etcd_root_password`, `demo_consumer_key`, `oidc_client_id`, `oidc_client_secret`,
   `openai_api_key`, `anthropic_api_key`, `azure_openai_api_key`
   (all `str = ""`), `etcd_storage_class: str = "local-path"` (or the
   cluster's default class), and a computed `apisix_enabled` that is
   `self.apisix.admin_key != ""`. Use `_all_or_none` for the OIDC pair.
2. `cluster.sample.toml`: an `[apisix]` block with those keys as commented
   REQUIRED/OPTIONAL lines, placed after `[localai]`.
3. `cluster.toml`: the same block at the same position (check-layout enforces
   section order). Generate keys with `openssl rand -hex 16`.
4. `just template schema`; add a valid fixture under
   `.github/template-tests/valid/` that sets `apisix.admin_key`, and list it in
   `template-e2e.yaml`'s fixture matrix.

Create the Pocket ID client by hand with callback
`https://apisix.<domain>/oauth2/callback`, then fill `oidc_client_id` and
`oidc_client_secret`.

## What the app does

- HelmRelease `apisix` from HelmRepository `apisix` (no OCI chart is published
  for apisix-helm-chart). Values are `deploy/kubernetes/values.yaml` with
  3 etcd replicas on the configured storage class.
- `ai.${SECRET_DOMAIN}` → `apisix-gateway:80` (data plane; API keys per route).
- `apisix.${SECRET_DOMAIN}` → `apisix-admin:9180` (Admin API and `/ui/`),
  behind Envoy Gateway's Pocket ID SecurityPolicy, group `cluster_admins`.
- Secrets: `apisix-admin` (admin/viewer keys), `apisix-etcd` (etcd RBAC root
  password; the etcd NetworkPolicy admits only APISIX pods), `apisix-provider-keys` (env vars
  that routes reference as `$env://OPENAI_AUTHORIZATION` and so on), `apisix-oidc`.
  LocalAI's key is reused from `localai.api_key` when `nvidia_enabled`, and
  the namespace carries `localai.ai/client: "true"` so LocalAI's NetworkPolicy
  admits APISIX. Reach it at `http://localai.ai.svc.cluster.local:8080/v1`.
- The restricted namespace needs the `postRenderers` patch in the HelmRelease
  (the chart's `wait-etcd` init container lacks a securityContext).

## Then

```bash
just configure            # render, sops-encrypt, kubeconform
git checkout -- ':(glob)bootstrap/**/*.sops.*' ':(glob)kubernetes/**/*.sops.*' ':(glob)talos/**/*.sops.*'
git add template/ kubernetes/apps/ai-gateway cluster.sample.toml cluster.schema.json
```

Add `docs/src/content/docs/apps/apisix.mdx` and a line in `apps/index.mdx`
per `.claude/rules/docs.md`. Not verified here: rendering with makejinja,
kubeconform, and the live cluster.
