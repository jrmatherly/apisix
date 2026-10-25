# AI gateway compose stack

Builds APISIX from this source tree with the dashboard from `dashboard/`
baked into `/ui/` (`docker/debian-dev/Dockerfile`), plus etcd, an
OpenAI-compatible mock model server, and optional Prometheus.

```bash
cd deploy/docker
cp .env.example .env            # set APISIX_ADMIN_KEY; provider keys as you have them
docker compose up -d --build    # add --profile monitoring for Prometheus on :9090
```

| URL | What |
|-----|------|
| http://localhost:9180/ui/ | Dashboard (enter the admin key in Settings, then refresh) |
| http://localhost:9180/apisix/admin/ | Admin API, header `X-API-KEY` |
| http://localhost:9080/ | Gateway |
| http://localhost:9091/apisix/prometheus/metrics | Metrics |

Secrets stay in `.env` (gitignored): the admin key is read by `config.yaml`
as `${{APISIX_ADMIN_KEY}}`, and provider keys reach routes as
`$env://OPENAI_AUTHORIZATION` and so on (listed under `nginx_config.envs`).

## Smoke test

```bash
set -a; source .env; set +a
../routes/admin-api.sh                      # demo consumer + five routes, all 201
curl -X POST localhost:9080/local/v1/chat/completions -H "apikey: $DEMO_CONSUMER_KEY" \
  -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"hello gateway"}]}'
```

The route answers `mock reply to: hello gateway` with a `usage` block. The mock
requires `Authorization: Bearer mock-token`, which the route only sends when
APISIX resolved `$env://LOCAL_LLM_AUTHORIZATION`: empty that variable in `.env`,
recreate `apisix`, and the same call returns the mock's 401. Without the
`apikey` header key-auth answers 401 before the upstream is reached. Once
20000 tokens are spent in a minute the route returns 503 with
`X-AI-RateLimit-Remaining-ai-proxy-openai-compatible: 0`.

To talk to a real Ollama on the Mac instead, set the route's
`override.endpoint` to `http://host.docker.internal:11434/v1/chat/completions`.
More routes: `deploy/routes/` and `docs/ai-gateway.md`.

Any change in the repo invalidates the `COPY . /apisix` layer, so a rebuild
recompiles the LuaRocks deps (a few minutes). `.dockerignore` keeps `.git`,
`deps` and `test-nginx` out of the context.
