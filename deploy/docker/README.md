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
`$env://OPENAI_API_KEY` and so on (listed under `nginx_config.envs`).

## Smoke test

```bash
source .env
curl -X PUT -H "X-API-KEY: $APISIX_ADMIN_KEY" localhost:9180/apisix/admin/routes/mock-chat -d '{
  "uri": "/mock/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-proxy": {"provider": "openai-compatible",
      "auth": {"header": {"Authorization": "Bearer $env://LOCAL_LLM_API_KEY"}},
      "options": {"model": "mock"},
      "override": {"endpoint": "http://mock-llm:8000/v1/chat/completions"}},
    "ai-rate-limiting": {"limit": 15, "time_window": 60, "limit_strategy": "total_tokens"}}}'
curl -X POST localhost:9080/mock/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hello gateway"}]}'
```

The first calls answer `mock reply to: hello gateway` with a `usage` block;
once 15 tokens are spent the route returns 503 with
`X-AI-RateLimit-Remaining-ai-proxy-openai-compatible: 0`.

To talk to a real Ollama on the Mac instead, set the route's
`override.endpoint` to `http://host.docker.internal:11434/v1/chat/completions`.
More routes: `deploy/routes/` and `docs/ai-gateway.md`.

Any change in the repo invalidates the `COPY . /apisix` layer, so a rebuild
recompiles the LuaRocks deps (a few minutes). `.dockerignore` keeps `.git`,
`deps` and `test-nginx` out of the context.
