# AI gateway guide (APISIX 3.19.0, this fork)

Lives in `docs/` beside the upstream plugin docs rather than under
`docs/en/latest/`, which mirrors apache/apisix and is published by its site
build; this page is fork-specific. Citations are `path:line` in this repo or a
full URL.

## Milestone: four providers, every shipped AI plugin

| Provider | ai-proxy `provider` | Native in 3.19? | Auth header | Endpoint |
|---|---|---|---|---|
| OpenAI | `openai` | yes (`apisix/plugins/ai-providers/openai.lua:38-49`) | `Authorization: $env://OPENAI_AUTHORIZATION` | default `api.openai.com` |
| Anthropic | `anthropic` | **yes** (`apisix/plugins/ai-providers/anthropic.lua:37-45`) | `x-api-key: $env://ANTHROPIC_API_KEY` + `anthropic-version` | default `api.anthropic.com`; `/v1/messages` URI gives Messages API semantics, `/chat/completions` gives OpenAI-chat semantics |
| Azure OpenAI | `azure-openai` | yes (`apisix/plugins/ai-providers/azure-openai.lua:26-36`) | `api-key: $env://AZURE_OPENAI_API_KEY` | `override.endpoint` required: full deployment URL with `api-version` (`docs/en/latest/plugins/ai-proxy.md:642-652`); body `model` is stripped |
| Ollama / LocalAI | `openai-compatible` | no Ollama provider (grep of `apisix/`, `docs/`, `t/` finds none) | `Authorization: $env://LOCAL_LLM_AUTHORIZATION` (LocalAI needs it, Ollama ignores it) | `override.endpoint: http://<host>:11434/v1/chat/completions` (`apisix/plugins/ai-providers/openai-compatible.lua:35-47`, scheme taken from the endpoint URL at `ai-providers/base.lua:196`) |

No provider adds an auth header for you except `auth.gcp` and `auth.aws`;
`auth.header` is forwarded verbatim (`apisix/plugins/ai-transport/http.lua:86-107`).

Secrets are never inline. `$env://NAME` reads an env var that must be listed
under `nginx_config.envs` (`conf/config.yaml.example:245`, rendered as nginx `env` directives by `apisix/cli/ngx_tpl.lua:58-59`;
`deploy/docker/apisix/config.yaml`, chart value `apisix.nginx.envs` in
`deploy/kubernetes/values.yaml`). `$secret://vault/...` or
`$secret://aws/...` / `$secret://gcp/...` use a configured secret provider
(`secret.md:49,76`). Consumer keys take the same references (`secret.md`'s
key-auth example).

What each plugin needs for this milestone:

| Plugin | Needs | Status for the milestone |
|---|---|---|
| ai-proxy, ai-proxy-multi | provider keys as env/secret refs | configured in `deploy/routes/`; proven against the compose mock |
| ai-rate-limiting | nothing external (`policy: local`); Redis for `policy: redis` | configured, proven (503 after the token budget) |
| ai-prompt-guard, ai-prompt-template, ai-prompt-decorator, ai-request-rewrite | nothing external (`ai-request-rewrite` calls an LLM of its own with the same provider schema) | guard and decorator configured |
| ai-cache | Redis. The default `exact` layer uses plain GET/SET (`apisix/plugins/ai-cache/schema.lua:78-85`, `ai-cache.lua:198,298`); only `layers: [exact, semantic]` needs Redis Stack with RediSearch (`apisix/plugins/ai-cache/vector-search/redis.lua:52,98`, `docs/en/latest/plugins/ai-cache.md:98`) plus `openai` or `azure_openai` embeddings (`ai-cache/schema.lua:106-134`) | not deployed: add a Redis service first |
| ai-rag | **Azure OpenAI embeddings + Azure AI Search only** (`apisix/plugins/ai-rag.lua:43-56`, `maxProperties = 1`) | not deployed: needs those two Azure resources |
| ai-aws-content-moderation | AWS Comprehend credentials + region | not deployed |
| ai-aliyun-content-moderation | Aliyun endpoint, region, access key pair | not deployed |
| ai-lakera-guard | Lakera `api_key` | not deployed |
| openapi-to-mcp | an OpenAPI URL reachable over HTTP (JSON or YAML) | not deployed |

All of them are enabled by default (`conf/config.yaml.example:593-622`,
`apisix/cli/config.lua:248-313`), so no `plugins:` list is needed.

Route and consumer configuration: `deploy/routes/apisix.yaml` (declarative,
standalone mode) and `deploy/routes/admin-api.sh` (Admin API). Both define a
`demo` key-auth consumer and routes `local-chat`, `openai-chat`,
`anthropic-messages`, `azure-chat`, and `llm` (ai-proxy-multi with weighted
fallback across Azure, OpenAI and Anthropic, per-instance token limits).

Per-plugin reference follows, verified against this checkout.

---

Verified against this checkout at 3.19.0 (`apisix/core/version.lua:23`). Online doc checked: https://apisix.apache.org/docs/apisix/plugins/ai-proxy/ (version 3.19.0; it agrees with the repo doc on the provider enum and on `override.endpoint` being required for openai-compatible, and does not mention Ollama). Other plugin pages were not fetched; the repo docs under `docs/en/latest/plugins/` are the same release branch.

Secret-reference syntax used in every example below: `$env://VARNAME` / `$ENV://VARNAME` and `$secret://$manager/$id/$secret_name/$key` (`docs/en/latest/terminology/secret.md:49`, `:76`, `:151`, `:221`). They work in "any string field in any plugin configuration" and are resolved in `plugin.filter()` at runtime (`secret.md:51`). Caveat: schema constraints on that field are bypassed (`secret.md:57`), and an unresolvable reference is used as a literal string with an error in error.log (`secret.md:63-65`). Standalone `apisix.yaml` must end with `#END` or it is not loaded (`docs/en/latest/deployment-modes.md:347`).

Plugins run in descending `priority` order (`apisix/plugin.lua:142-143`, sort at `:321`). Higher number = earlier.

---

## 0. Summary tables

### Priorities (from `priority =` in each file)

| Plugin | Priority | Source |
|---|---|---|
| ai (NOT an AI plugin: route-match cache accelerator) | 22900 | `apisix/plugins/ai.lua:58` |
| ai-request-rewrite | 1073 | `apisix/plugins/ai-request-rewrite.lua:118` |
| ai-prompt-guard | 1072 | `apisix/plugins/ai-prompt-guard.lua:62` |
| ai-prompt-template | 1071 | `apisix/plugins/ai-prompt-template.lua:82` |
| ai-prompt-decorator | 1070 | `apisix/plugins/ai-prompt-decorator.lua:63` |
| ai-rag | 1060 | `apisix/plugins/ai-rag.lua:82` |
| ai-proxy-multi | 1041 | `apisix/plugins/ai-proxy-multi.lua:75` |
| ai-proxy | 1040 | `apisix/plugins/ai-proxy.lua:29` |
| ai-cache | 1035 | `apisix/plugins/ai-cache.lua:42` |
| ai-aws-content-moderation | 1031 | `apisix/plugins/ai-aws-content-moderation.lua:193` |
| ai-rate-limiting | 1030 | `apisix/plugins/ai-rate-limiting.lua:176` |
| ai-aliyun-content-moderation | 1029 | `apisix/plugins/ai-aliyun-content-moderation.lua:126` |
| ai-lakera-guard | 1028 | `apisix/plugins/ai-lakera-guard.lua:31` |
| openapi-to-mcp | 540 | `apisix/plugins/openapi-to-mcp.lua:70` |

So every `ai-prompt-*`, `ai-request-rewrite` and `ai-rag` runs before `ai-proxy`/`ai-proxy-multi` (they mutate the request body first); `ai-cache`, `ai-rate-limiting`, both moderation plugins and `ai-lakera-guard` have lower priorities and consume `ctx` fields that ai-proxy sets (`ctx.picked_ai_instance_name`, `ctx.ai_client_protocol`, `ctx.ai_token_usage`).

Caveat found: `conf/config.yaml.example:598` comments `ai-aws-content-moderation # priority: 1050`, but the code says 1031 (`ai-aws-content-moderation.lua:193`). The comment is stale; the code value is what sorts.

### Default `plugins:` entries in `conf/config.yaml.example` (all enabled, i.e. uncommented)

```
  - ai                             # priority: 22900      (line 545)
  - ai-request-rewrite             # priority: 1073       (593)
  - ai-prompt-guard                # priority: 1072       (594)
  - ai-prompt-template             # priority: 1071       (595)
  - ai-prompt-decorator            # priority: 1070       (596)
  - ai-rag                         # priority: 1060       (597)
  - ai-aws-content-moderation      # priority: 1050       (598)  <- comment stale, code = 1031
  - ai-proxy-multi                 # priority: 1041       (599)
  - ai-proxy                       # priority: 1040       (600)
  - ai-cache                       # priority: 1035       (601)
  - ai-rate-limiting               # priority: 1030       (602)
  - ai-aliyun-content-moderation   # priority: 1029       (603)
  - ai-lakera-guard                # priority: 1028       (604)
  - openapi-to-mcp                 # priority: 540        (622)

```

Also `plugin_attr.ai-proxy.http_client: ngx_http_ffi_client` (alternative `lua-resty-http`) at `conf/config.yaml.example:685-687`, shared by ai-proxy and ai-proxy-multi.

### Native providers (`apisix/plugins/ai-providers/`)

Enum (`apisix/plugins/ai-providers/schema.lua:21-25`): `openai, deepseek, aimlapi, anthropic, openai-compatible, azure-openai, openrouter, gemini, vertex-ai, bedrock`. **`anthropic` and `azure-openai` are both native in 3.19** (files below). There is **no `ollama` provider file** and the string "ollama"/"11434" appears nowhere in `apisix/`, `docs/` or `t/` (grep returned nothing).

| provider file | default host | capabilities → path | auth mechanism |
|---|---|---|---|
| `openai.lua:38-49` | `api.openai.com:443` | openai-chat `/v1/chat/completions`, openai-responses `/v1/responses`, openai-embeddings `/v1/embeddings` | whatever you put in `auth.header`/`auth.query` (no provider sets a header itself) |
| `deepseek.lua:28-32` | `api.deepseek.com:443` | openai-chat `/chat/completions` | same |
| `aimlapi.lua:28-32` | `api.aimlapi.com:443` | openai-chat `/chat/completions` | same |
| `anthropic.lua:37-45` | `api.anthropic.com:443` | openai-chat `/v1/chat/completions`, anthropic-messages `/v1/messages` | same (put `x-api-key` + `anthropic-version` in `auth.header`; nothing is added automatically — `ai-transport/http.lua:86-107` only copies client headers, overlays `auth.header`, forces `content-type: application/json` and strips host/content-length/accept-encoding) |
| `openrouter.lua:28-32` | `openrouter.ai:443` | openai-chat `/api/v1/chat/completions` | same |
| `gemini.lua:28-32` | `generativelanguage.googleapis.com:443` | openai-chat `/v1beta/openai/chat/completions` | same |
| `openai-compatible.lua:35-47` | **none** | openai-chat `/v1/chat/completions`, openai-responses `/v1/responses`, openai-embeddings `/v1/embeddings` | same; host must come from `override.endpoint` |
| `azure-openai.lua:26-36` | **none**; `remove_model = true` | openai-chat `/completions` | same (`api-key` header per docs example `docs/en/latest/plugins/ai-proxy.md:642-652`); host from `override.endpoint` |
| `vertex-ai.lua:22-27,44-55,66-95` | `{region}-aiplatform.googleapis.com` (or `aiplatform.googleapis.com` with no region) | openai-chat `/v1beta1/projects/{p}/locations/{r}/endpoints/openapi/chat/completions`, vertex-predict `/v1/projects/{p}/locations/{r}/publishers/google/models/{model}:predict` | `auth.gcp` → OAuth2 bearer token fetched from service-account JSON or env `GCP_SERVICE_ACCOUNT` (`ai-providers/base.lua:244-250`, `ai-transport/auth.lua:43-51`) |
| `bedrock.lua:22-24,28-62` | `bedrock-runtime.{region}.amazonaws.com`; `remove_model = true`, `aws_sigv4 = true`, `streaming_framing = "aws-eventstream"` | bedrock-converse `/model/{model}/converse` or `/converse-stream` | `auth.aws` → SigV4 (`ai-transport/auth-aws.lua:64-146`) |

Host/endpoint resolution: `override.endpoint` is parsed; its host/scheme/port win, its path wins if present, otherwise the capability path is used (`ai-providers/base.lua:192-232`, host fallback chain `:281-282`: parsed_url.host → capability host → `self.host`). For `openai-compatible`/`azure-openai`, which have no `self.host`, omitting `override.endpoint` leaves `host = nil` at request time. **ai-proxy does not reject that at config time**: `validate_provider_requirements` only checks `vertex-ai` and `bedrock` (`apisix/plugins/ai-proxy/schema.lua:561-589`). Only `ai-request-rewrite` enforces it (`ai-request-rewrite.lua:169-177`). The doc states it as required (`docs/en/latest/plugins/ai-proxy.md:88`).

### Protocols (`apisix/plugins/ai-protocols/`)

Registered: `openai-chat`, `openai-responses`, `openai-embeddings`, `anthropic-messages`, `bedrock-converse`, `passthrough` (`ai-protocols/init.lua:31-38`). **There is no schema field to pick the protocol.** The client protocol is auto-detected from URI + body, in this order (`init.lua:42-49`):

| protocol | matches when | source |
|---|---|---|
| bedrock-converse | URI ends `/converse` and body has `messages` | `bedrock-converse.lua:35-39` |
| anthropic-messages | URI ends `/v1/messages` and body is JSON object | `anthropic-messages.lua:79-82` |
| openai-responses | URI ends `/v1/responses` and body has `input` | `openai-responses.lua:35-39` |
| openai-chat | body has `messages` | `openai-chat.lua:83-85` |
| openai-embeddings | body has `input` | `openai-embeddings.lua:29-31` |
| passthrough | any non-empty JSON object | `passthrough.lua:29-31` |

Then ai-proxy maps client protocol → provider capability: native if the provider lists it; `passthrough` forwards the original URI/method/query; otherwise a converter is searched (`ai-proxy/base.lua:237-261`). Converters present: `anthropic-messages-to-openai-chat.lua`, `openai-embeddings-to-vertex-predict.lua` (`ai-protocols/converters/`). So a route's URI decides the protocol: expose `/v1/messages` to get Anthropic Messages semantics, `/v1/chat/completions` (or any other URI with a `messages` body) for OpenAI chat. The only protocol-named schema field is `override.request_body.<protocol-name>` (`ai-proxy/schema.lua:90-110`).

---

## 1. ai-proxy

Purpose: single-upstream LLM proxy; rewrites the request to the provider's endpoint, injects auth, parses usage (`apisix/plugins/ai-proxy.lua`, `ai-proxy/base.lua`).

Schema `apisix/plugins/ai-proxy/schema.lua:331-400` (`_M.ai_proxy_schema`):

- required: `provider` (enum above, `:334-338`), `auth` (`:341`, `:395`).
- `auth` (`:33-73`): `header{}` / `query{}` string maps (`:24-31`), `gcp{service_account_json,max_ttl,expire_early_secs=60}` (`:38-60`), `aws{access_key_id,secret_access_key,session_token}` (`:61-70`). `additionalProperties=false`.
- `options` (`:75-88`): `model` plus any extra keys, flat-overwritten into the body (`ai-providers/base.lua:75-83`). `options.model` takes precedence over body `model` (`ai-proxy/base.lua:267-271`).
- `override` (`:127-155`): `endpoint`, `llm_options.max_tokens` (`:112-125`, always force-overwrites, mapped per provider), `request_body.<protocol>` deep-merge, `request_body_force_override=false`.
- `provider_conf{project_id,region}` (`:157-167`), `timeout=30000` ms max 600000 (`:343-349`), `max_req_body_size=64MiB` (`:350`), `max_stream_duration_ms`, `max_response_bytes`, `keepalive=true`, `keepalive_timeout=60000`, `keepalive_pool=30`, `streaming_flush_interval_ms=10`, `ssl_verify=true` (`:392`), `logging{summaries,payloads}` (`:315-329`).
- `encrypt_fields`: `auth.header`, `auth.query`, `auth.gcp.service_account_json`, `auth.aws.secret_access_key`, `auth.aws.session_token` (`:396-399`).
- Extra validation in `check_schema` (`ai-proxy.lua:35-53`): provider module must load; non-secret `service_account_json` must be valid JSON; vertex-ai needs `provider_conf` or `override.endpoint`; bedrock needs `provider_conf.region` and `auth.aws` (`schema.lua:561-589`).

Behaviour proven from code:

- Instance name seen by ai-rate-limiting is `"ai-proxy-" .. conf.provider` (`ai-proxy.lua:65`).
- Upstream is bypassed (`ctx.bypass_nginx_upstream = true`, `ai-proxy.lua:68`); the route's `upstream` is irrelevant but the Admin API still requires a route to be valid, so docs examples put a dummy one.
- "X-API-KEY style" auth: yes, any header name in `auth.header` is sent verbatim (lowercased key) — `ai-transport/http.lua:97-99`. Nothing sets `Authorization` for you except `auth.gcp`.
- Ollama: use `provider: openai-compatible` with `override.endpoint: http://ollama:11434/v1/chat/completions` (or scheme+host only, path then defaults to `/v1/chat/completions`, `openai-compatible.lua:38`; `ai-providers/base.lua:217-222`). The scheme comes from the parsed endpoint, default https (`base.lua:196`), so plain `http` works. This is derived from code; there is no Ollama example in repo or online docs (unverified as a tested configuration).

Minimal route (Admin API body, OpenAI):

```json
{
  "uri": "/v1/chat/completions",
  "methods": ["POST"],
  "plugins": {
    "ai-proxy": {
      "provider": "openai",
      "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } },
      "options": { "model": "gpt-4o-mini" }
    }
  }

}
```

Same, Anthropic native (expose Messages API):

```json
{
  "uri": "/v1/messages",
  "methods": ["POST"],
  "plugins": {
    "ai-proxy": {
      "provider": "anthropic",
      "auth": { "header": { "x-api-key": "$secret://vault/1/llm/anthropic-key", "anthropic-version": "2023-06-01" } },
      "options": { "model": "claude-sonnet-4-5" }
    }
  }

}
```

Same, Ollama via openai-compatible:

```json
{
  "uri": "/ollama/chat",
  "methods": ["POST"],
  "plugins": {
    "ai-proxy": {
      "provider": "openai-compatible",
      "auth": { "header": { "Authorization": "$env://LOCAL_LLM_AUTHORIZATION" } },
      "options": { "model": "llama3.1" },
      "override": { "endpoint": "http://ollama:11434/v1/chat/completions" }
    }
  }

}
```

(`auth` is a required object even when the backend ignores it; the `patternProperties` schema accepts an empty `{}` header map — `schema.lua:24-31` — unverified at runtime whether `auth: {}` passes `required` on nested keys; a dummy header is the safe form.)

Standalone YAML (`conf/apisix.yaml`):

```yaml
routes:
  - id: openai-chat
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

Caveats: Azure needs `override.endpoint` set to the full deployment URL incl. `api-version` and `auth.header.api-key` (`docs/en/latest/plugins/ai-proxy.md:642-652`); `azure-openai` strips `model` from the body (`azure-openai.lua:29`). Bedrock streaming is opted-in by `body.stream=true` and uses `/converse-stream` with AWS EventStream framing (`bedrock-converse.lua:43-47`, `bedrock.lua:22-24,59-63`).

---

## 2. ai-proxy-multi

Purpose: same as ai-proxy with N instances, load balancing, health checks, retries/fallback (`apisix/plugins/ai-proxy-multi.lua`).

Schema `apisix/plugins/ai-proxy/schema.lua:402-559` (`_M.ai_proxy_multi_schema`):

- required: `instances` (`:549`); each instance requires `name, provider, auth, weight` (`:228`), optional `priority=0`, `options`, `override`, `provider_conf`, `checks.active` (`:202-208`, uses `schema_def.health_checker_active`), semantic `examples[]`/`threshold`.
- `balancer.algorithm` ∈ `chash|roundrobin|semantic`, default roundrobin, `hash_on`, `key` (`:405-437`).
- `fallback_strategy`: string `instance_health_and_rate_limiting|http_429|http_5xx` or array of `rate_limiting|http_429|http_5xx` (`:441-455`). `fallback_http_statuses[]` 400-599 (`:456-476`), `max_retries` (`:477-486`), `retry_on_failure_within_ms` (`:487-497`).
- `semantic_opts.embeddings{provider∈openai|azure-openai, model, endpoint, auth.header/query, timeout=3000, ssl_verify}` required when algorithm is semantic (`:232-313`).
- Same timeout/keepalive/size/ssl_verify fields as ai-proxy (`:498-547`).
- `encrypt_fields` cover every instance's auth and the embeddings auth (`:550-558`).

Proven: fallback_strategy and health checks are implemented — `fallback_strategy_has` (`ai-proxy-multi.lua:80`), rate-limiting-aware pick (`:661-662`), 429/5xx/extra-status retry with `retry_on_failure_within_ms` and `max_retries` (`:944-969`), per-instance `checks` → `healthcheck_manager.fetch_checker` (`:627-637`, `:1003-1006`, `:1045-1071`). Semantic algorithm does not participate in health checks or fallback (`schema.lua:411-418`). Docs note OpenAI/DeepSeek/AIMLAPI have no official health endpoint (`docs/en/latest/plugins/ai-proxy-multi.md:110`). Endpoint resolution per instance: `override.endpoint` else provider `get_node`/`host` (`:387-412`), with DNS re-resolution (`:421-432`).

Admin API body:

```json
{
  "uri": "/v1/chat/completions",
  "methods": ["POST"],
  "plugins": {
    "ai-proxy-multi": {
      "fallback_strategy": ["rate_limiting", "http_429", "http_5xx"],
      "max_retries": 1,
      "instances": [
        { "name": "openai-primary", "provider": "openai", "weight": 8,
          "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } },
          "options": { "model": "gpt-4o-mini" } },
        { "name": "anthropic-backup", "provider": "anthropic", "weight": 2,
          "auth": { "header": { "x-api-key": "$secret://vault/1/llm/anthropic-key", "anthropic-version": "2023-06-01" } },
          "options": { "model": "claude-sonnet-4-5" } }
      ]
    }
  }

}
```

Standalone:

```yaml
routes:
  - id: llm-multi
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-proxy-multi:
        fallback_strategy: ["rate_limiting", "http_429", "http_5xx"]
        max_retries: 1
        instances:
          - name: openai-primary
            provider: openai
            weight: 8
            auth:
              header:
                Authorization: "$env://OPENAI_AUTHORIZATION"
            options:
              model: gpt-4o-mini
          - name: anthropic-backup
            provider: anthropic
            weight: 2
            auth:
              header:
                x-api-key: "$secret://vault/1/llm/anthropic-key"
                anthropic-version: "2023-06-01"
            options:
              model: claude-sonnet-4-5

#END
```

Caveat: the second instance above mixes an OpenAI-chat client protocol with Anthropic; that works because `anthropic.lua:40-43` lists `openai-chat` natively at `/v1/chat/completions` (Anthropic's OpenAI-compat endpoint), not through the converter.

---

## 3. ai-rate-limiting

Purpose: token-based rate limit per LLM instance, counted after the response in the `log` phase (`apisix/plugins/ai-rate-limiting.lua:434-466`).

Schema `ai-rate-limiting.lua:53-172`: `limit` + `time_window` (route-wide, integers or strings/vars), or `instances[{name,limit,time_window}]` (`:33-51`), or `rules[{count,time_window,key,header_prefix}]` (`:101-126`); `oneOf` at `:132-146`. `limit_strategy` ∈ `total_tokens|prompt_tokens|completion_tokens|expression` default `total_tokens` (`:69-74`); `cost_expr` Lua arithmetic over raw usage fields when `expression` (`:75-83`, required then `:212-214`). `rejected_code=503`, `rejected_msg`, `policy` ∈ `local|redis|redis-cluster|redis-sentinel` (`:95-99`) with limit-count's redis fields, `allow_degradation`, `show_limit_quota_header=true`. `encrypt_fields`: `redis_password`, `sentinel_password` (`:171`).

What it counts: `ctx.ai_token_usage[limit_strategy]` (`:426-430`), or `cost_expr` evaluated over `ctx.llm_raw_usage` (`:412-424`). Those are filled by the provider base from the protocol's `extract_usage` (`ai-providers/base.lua:34-61`); for openai-chat that is `usage.prompt_tokens/completion_tokens/total_tokens` plus cache/reasoning details (`ai-protocols/openai-chat.lua:217-231`); Anthropic usage is normalised by `to_usage` (`anthropic-messages.lua:201-207`), with split streaming events merged (`base.lua:43-49`). Zero usage skips counting (`:449-452`). Instance match key = `ctx.picked_ai_instance_name` (`:296`, `:435`): `"ai-proxy-<provider>"` for ai-proxy (`ai-proxy.lua:65`) or the instance `name` for ai-proxy-multi (`ai-proxy-multi.lua:932`). An instance not listed falls back to the top-level `limit` if set (`:274-283`). With ai-proxy-multi `fallback_strategy` rate_limiting, a limited instance is skipped (`ai-proxy-multi.lua:661-662`).

Admin API:

```json
{
  "uri": "/v1/chat/completions",
  "methods": ["POST"],
  "plugins": {
    "ai-proxy": {
      "provider": "openai",
      "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } },
      "options": { "model": "gpt-4o-mini" }
    },
    "ai-rate-limiting": {
      "limit_strategy": "total_tokens",
      "instances": [ { "name": "ai-proxy-openai", "limit": 10000, "time_window": 60 } ]
    }
  }

}
```

Standalone:

```yaml
routes:
  - id: llm-limited
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini
      ai-rate-limiting:
        limit_strategy: total_tokens
        instances:
          - name: ai-proxy-openai
            limit: 10000
            time_window: 60

#END
```

---

## 4. ai-prompt-guard

Purpose: regex allow/deny on prompt content before the LLM (`apisix/plugins/ai-prompt-guard.lua`).

Schema `:28-58`: `allow_patterns[]`, `deny_patterns[]` (PCRE, validated at `:73-86`, matched with `ngx.re.find(..., "jou")` `:177,189`), `match_all_roles=false` (default checks only `role == "user"`, `:152-156`), `match_all_conversation_history=false` (`:93`), `max_req_body_size`, `fail_mode` ∈ `skip|warn|error` default skip (`:56`, defined in `ai-protocols/binding.lua:52-64`). Messages come from the auto-detected protocol (`:145`). No required fields.

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-prompt-guard": { "deny_patterns": ["(?i)ignore (all|previous) instructions"], "match_all_roles": false },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: guarded
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-prompt-guard:
        deny_patterns: ["(?i)ignore (all|previous) instructions"]
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

---

## 5. ai-prompt-template

Purpose: client sends `{"template_name": ..., <vars>}`; plugin renders a stored `messages`/`model` template into the body (`ai-prompt-template.lua:125-144`, body then handed to body-transformer-style rendering `:140`).

Schema `:41-77`: required `templates[]` with `name` and `template{model, messages[{role∈system|user|assistant, content}]}` (`:21-33`, `:51-74`). `max_req_body_size`. Missing/unknown `template_name` → 400 (`:129-137`).

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-prompt-template": { "templates": [ { "name": "summarize", "template": { "model": "gpt-4o-mini",
        "messages": [ { "role": "system", "content": "Summarize in {{ language }}." }, { "role": "user", "content": "{{ text }}" } ] } } ] },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } } }
  } }

```

```yaml
routes:
  - id: templated
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-prompt-template:
        templates:
          - name: summarize
            template:
              model: gpt-4o-mini
              messages:
                - role: system
                  content: "Summarize in {{ language }}."
                - role: user
                  content: "{{ text }}"
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"

#END
```

(Template variable syntax is `{{variable_name}}`, filled from the request body — `docs/en/latest/plugins/ai-prompt-template.md:52`, examples `:110-114`, `template_name` in the request at `:287`.)

---

## 6. ai-prompt-decorator

Purpose: prepend/append fixed messages to the conversation, protocol-aware (`ai-prompt-decorator.lua:89-96` via `protocols.prepend_messages/append_messages`).

Schema `:40-58`: `prepend[]` and/or `append[]` of `{role, content}` (`:21-33`); `anyOf` requires at least one; `max_req_body_size`.

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-prompt-decorator": { "prepend": [ { "role": "system", "content": "You are a terse assistant." } ] },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: decorated
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-prompt-decorator:
        prepend:
          - role: system
            content: "You are a terse assistant."
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

---

## 7. ai-request-rewrite

Purpose: sends the incoming request body plus `prompt` to an LLM and replaces the body with the LLM's answer before proxying to the normal upstream (`ai-request-rewrite.lua:182-201`).

Schema `:60-114`: required `prompt`, `provider` (same enum), `auth{header,query}` (`:38-45`, no gcp/aws); `options.model` etc. (`:47-58`), `timeout=30000` max 60000, `keepalive`, `keepalive_pool`, `ssl_verify=true`, `override.endpoint` (`:102-111`). `check_schema` rejects `openai-compatible` without `override.endpoint` (`:169-177`). It loads the same `ai-providers.<provider>` module and uses its protocol/path (`:124-165`).

```json
{ "uri": "/rewrite", "methods": ["POST"],
  "plugins": { "ai-request-rewrite": { "prompt": "Translate the JSON body to English, keep keys.", "provider": "openai",
      "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } } },
  "upstream": { "type": "roundrobin", "nodes": { "backend:8080": 1 } } }

```

```yaml
routes:
  - id: rewrite
    uri: /rewrite
    methods: ["POST"]
    plugins:
      ai-request-rewrite:
        prompt: "Translate the JSON body to English, keep keys."
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini
    upstream:
      type: roundrobin
      nodes:
        "backend:8080": 1

#END
```

---

## 8. ai-cache

Purpose: Redis-backed response cache for LLM calls; L1 exact fingerprint, optional L2 semantic vector search (`apisix/plugins/ai-cache.lua`, `ai-cache/schema.lua`).

Schema `ai-cache/schema.lua:24-170`: `policy` only `redis` (`:72-76`) with the shared redis fields merged in (`:22`, `:150-157`: `redis_host`, `redis_port`, `redis_password`…); `layers` ⊆ `exact|semantic`, must contain `exact`, default `["exact"]` (`:78-85`); `exact.ttl=3600` (`:27-33`); `cache_key{share_across_routes,include_consumer,include_vars}` (`:35-47`); `max_cache_body_size=1MiB`, `cache_headers=true`, `bypass_on[{header,equals}]`, `fail_mode`. `semantic` (required when `layers` has semantic, `:158-164`): `similarity_threshold=0.95`, `top_k=1`, `distance_metric=cosine`, `ttl=86400`, `match{...}`, `embedding` = exactly one of `openai{model,api_key required; endpoint default https://api.openai.com/v1/embeddings}` or `azure_openai{endpoint,api_key required}` (`:106-134`; endpoints in `ai-cache/embeddings/openai.lua:21,33`, `azure_openai.lua:28-31` sends `api-key`), `vector_search.redis.index="ai-cache"` (`:135-145`). Encrypted: `redis_password`, both `api_key`s (`:165-169`).

External dependencies: **Redis**. The default `exact` layer uses plain GET/SET (`ai-cache.lua:198,298`); the `semantic` layer uses `FT.CREATE`/`FT.SEARCH` (`ai-cache/vector-search/redis.lua:52,98`) and therefore needs Redis Stack with RediSearch (`docs/en/latest/plugins/ai-cache.md:98-100`). **Embeddings — openai or azure_openai only** (`ai-cache/embeddings/`). No qdrant/azure_ai_search in ai-cache.

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-cache": { "redis_host": "redis", "redis_port": 6379, "redis_password": "$env://REDIS_PASSWORD", "exact": { "ttl": 600 } },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: cached
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-cache:
        redis_host: redis
        redis_port: 6379
        redis_password: "$env://REDIS_PASSWORD"
        exact:
          ttl: 600
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

Semantic layer addition: `layers: ["exact","semantic"]`, `semantic.embedding.openai: {model: text-embedding-3-small, api_key: "$env://OPENAI_AUTHORIZATION"}`, `semantic.vector_search.redis: {}`. `check_schema` warns when `semantic` is configured but not listed in `layers` (`ai-cache.lua:68-71`) and warns on non-https embedding endpoints (`:60-63`).

---

## 9. ai-rag

Purpose: embeds the query, runs a vector search, injects results into the prompt before ai-proxy (`apisix/plugins/ai-rag.lua`).

Schema `:31-64`: required `embeddings_provider.azure_openai{endpoint, api_key}` (`ai-rag/embeddings/azure_openai.lua:24-34`, sends `api-key` header `:47`) and `vector_search_provider.azure_ai_search{endpoint, api_key}` (`ai-rag/vector-search/azure_ai_search.lua:23-33`, `api-key` header `:56`); `maxProperties = 1` on each with a comment that other providers are not yet implemented (`:43-46`, `:53-56`). `ssl_verify=true`. Encrypted: both `api_key`s (`:60-63`). The client request must carry `ai_rag.embeddings` and `ai_rag.vector_search` objects (`:66-78`; embeddings needs `input`, search needs `fields`: `embeddings/azure_openai.lua:79-86`, `vector-search/azure_ai_search.lua:74-81`).

External dependencies: **only Azure OpenAI embeddings + Azure AI Search** in 3.19 (`find apisix/plugins/ai-rag -type f` returns exactly those two files). No redis/qdrant.

```json
{ "uri": "/rag", "methods": ["POST"],
  "plugins": {
    "ai-rag": {
      "embeddings_provider": { "azure_openai": { "endpoint": "https://RES.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01", "api_key": "$secret://vault/1/azure/openai-key" } },
      "vector_search_provider": { "azure_ai_search": { "endpoint": "https://SEARCH.search.windows.net/indexes/INDEX/docs/search?api-version=2024-07-01", "api_key": "$secret://vault/1/azure/search-key" } }
    },
    "ai-proxy": { "provider": "azure-openai", "auth": { "header": { "api-key": "$secret://vault/1/azure/openai-key" } },
      "override": { "endpoint": "https://RES.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview" } }
  } }

```

```yaml
routes:
  - id: rag
    uri: /rag
    methods: ["POST"]
    plugins:
      ai-rag:
        embeddings_provider:
          azure_openai:
            endpoint: "https://RES.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01"
            api_key: "$secret://vault/1/azure/openai-key"
        vector_search_provider:
          azure_ai_search:
            endpoint: "https://SEARCH.search.windows.net/indexes/INDEX/docs/search?api-version=2024-07-01"
            api_key: "$secret://vault/1/azure/search-key"
      ai-proxy:
        provider: azure-openai
        auth:
          header:
            api-key: "$secret://vault/1/azure/openai-key"
        override:
          endpoint: "https://RES.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview"

#END
```

(Azure URL shapes and api-versions are placeholders, not taken from the repo.)

---

## 10. ai-aws-content-moderation

Purpose: AWS Comprehend `DetectToxicContent` on request and/or response messages (`ai-aws-content-moderation.lua:44`).

Schema `:56-187`: required `comprehend{access_key_id, secret_access_key, region}` (`:59-74`, optional `endpoint`, `ssl_verify=true`); `moderation_categories{PROFANITY|HATE_SPEECH|INSULT|…: number}` (`:54`, `:76-86`), `moderation_threshold=0.5` (`:87-91`), `check_request=true`, `check_response=false` (`:93-94`), roles default all four (`:96-100`), streaming mode default `final_packet` (`:137-139`), `deny_code=200` (`:157-161`), `deny_message`, timeout 10000, keepalive, `fail_mode`. Encrypted: `comprehend.secret_access_key` (`:186`).

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-aws-content-moderation": { "comprehend": { "access_key_id": "$env://AWS_ACCESS_KEY_ID", "secret_access_key": "$env://AWS_SECRET_ACCESS_KEY", "region": "us-east-1" }, "moderation_threshold": 0.6 },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: moderated-aws
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-aws-content-moderation:
        comprehend:
          access_key_id: "$env://AWS_ACCESS_KEY_ID"
          secret_access_key: "$env://AWS_SECRET_ACCESS_KEY"
          region: us-east-1
        moderation_threshold: 0.6
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

Caveat: priority 1031 is below ai-proxy (1040), so request-side moderation runs after ai-proxy's `access` but before `before_proxy` sends the upstream request (ai-proxy defers the call to `before_proxy`, `ai-proxy.lua:72`); it relies on `ctx.ai_client_protocol` set by ai-proxy.

---

## 11. ai-aliyun-content-moderation

Purpose: Alibaba Cloud Green (LLM query/response moderation) on request and/or response (`ai-aliyun-content-moderation.lua`).

Schema `:35-121`: required `endpoint, region_id, access_key_id, access_key_secret` (`:58-61`, `:120`); `check_request=true`, `check_response=false` (`:63-64`), roles default `["user"]` (`:76-80`), `request_check_service="llm_query_moderation"`, `response_check_service="llm_response_moderation"`, length limits 2000/5000 (`:90-94`), `risk_level_bar="high"` (`:95-97`), `deny_code=200` (`:99-103`), `deny_message`, streaming mode `final_packet` (`:39-41`), timeout 10000, keepalive, `ssl_verify`, `fail_mode`. Encrypted: `access_key_secret` (`:119`).

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-aliyun-content-moderation": { "endpoint": "https://green-cip.cn-shanghai.aliyuncs.com", "region_id": "cn-shanghai", "access_key_id": "$env://ALIYUN_AK_ID", "access_key_secret": "$env://ALIYUN_AK_SECRET" },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: moderated-aliyun
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-aliyun-content-moderation:
        endpoint: "https://green-cip.cn-shanghai.aliyuncs.com"
        region_id: cn-shanghai
        access_key_id: "$env://ALIYUN_AK_ID"
        access_key_secret: "$env://ALIYUN_AK_SECRET"
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

(Endpoint host is the conventional Green-CIP one; not read from the repo doc — unverified.)

---

## 12. ai-lakera-guard

Purpose: Lakera Guard v2 prompt-injection / content screening on input, output or both (`ai-lakera-guard.lua`, `ai-lakera-guard/schema.lua`, `client.lua`).

Schema `ai-lakera-guard/schema.lua:21-100`: required `api_key` (sent as `Authorization: Bearer`, `client.lua:62-63`); `lakera_endpoint` default `https://api.lakera.ai/v2/guard` (`:29-34`), `project_id`, `direction` ∈ `input|output|both` default input (`:39-44`), `action` ∈ `block|alert` (`:45-54`), `fail_open=false` (`:55-59`), `fail_mode`, `timeout=5000`, `ssl_verify=true`, `reveal_failure_categories=false`, `deny_code=200` (`:77-86`), request/response failure messages. Encrypted: `api_key` (`:98`).

```json
{ "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "ai-lakera-guard": { "api_key": "$secret://vault/1/lakera/api-key", "direction": "both", "deny_code": 400 },
    "ai-proxy": { "provider": "openai", "auth": { "header": { "Authorization": "$env://OPENAI_AUTHORIZATION" } }, "options": { "model": "gpt-4o-mini" } }
  } }

```

```yaml
routes:
  - id: lakera
    uri: /v1/chat/completions
    methods: ["POST"]
    plugins:
      ai-lakera-guard:
        api_key: "$secret://vault/1/lakera/api-key"
        direction: both
        deny_code: 400
      ai-proxy:
        provider: openai
        auth:
          header:
            Authorization: "$env://OPENAI_AUTHORIZATION"
        options:
          model: gpt-4o-mini

#END
```

---

## 13. openapi-to-mcp

Purpose: serves an MCP server (tools generated from an OpenAPI 3.x document) over SSE or Streamable HTTP, calling the REST API at `base_url` (`openapi-to-mcp.lua`, `openapi-to-mcp/`).

Schema `openapi-to-mcp.lua:23-64`: required `openapi_url`, `base_url` (`:63`); `transport` ∈ `sse|streamable_http` default `sse` (`:26-31`); `headers{}` forwarded to the external service (`:42-53`); `flatten_parameters=false` (`:54-61`). `base_url` and `headers` values support nginx-variable interpolation (`:81-102`). Input: the spec is fetched over HTTP GET from `openapi_url` (`openapi-to-mcp/openapi/loader.lua:182-188`), parsed as JSON then YAML via `lyaml` (`loader.lua:133-135`); doc states OpenAPI 3.x JSON or YAML with internal and http(s) `$ref` (`docs/en/latest/plugins/openapi-to-mcp.md:43`). Streamable HTTP answers in-process and bypasses the upstream (`:105-120`). Not an LLM-calling plugin; no provider key.

`headers` values go through `core.utils.resolve_var` for `${var}` request variables only (`openapi-to-mcp.lua:81-98`); a `$env://` or `$secret://` reference is resolved by the plugin runner only when it is the whole value (`apisix/plugin.lua:101-113`, `apisix/secret.lua:214`). So the env var below holds the complete `Bearer ...` string, as with the ai-proxy routes. A per-request alternative is a `${http_x_api_token}` variable (`docs/en/latest/plugins/openapi-to-mcp.md:52`).

```json
{ "uri": "/mcp", "methods": ["GET", "POST", "DELETE"],
  "plugins": { "openapi-to-mcp": { "transport": "streamable_http",
      "openapi_url": "https://petstore3.swagger.io/api/v3/openapi.json",
      "base_url": "https://petstore3.swagger.io/api/v3",
      "headers": { "Authorization": "$env://PETSTORE_AUTHORIZATION" } } },
  "upstream": { "type": "roundrobin", "nodes": { "127.0.0.1:1980": 1 } } }

```

```yaml
routes:
  - id: mcp
    uri: /mcp
    methods: ["GET", "POST", "DELETE"]
    plugins:
      openapi-to-mcp:
        transport: streamable_http
        openapi_url: "https://petstore3.swagger.io/api/v3/openapi.json"
        base_url: "https://petstore3.swagger.io/api/v3"
        headers:
          Authorization: "$env://PETSTORE_AUTHORIZATION"
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1

#END
```

(`methods` list and dummy upstream follow the doc's example at `openapi-to-mcp.md:84-88`; whether DELETE is needed depends on client session termination — unverified.)

---

## 14. `ai.lua` (for completeness)

`apisix/plugins/ai.lua` (priority 22900, `:58`) is the route-matching cache accelerator (builds a cache key from uri/method/host, `:38-49`); it has nothing to do with LLMs and is on by default (`conf/config.yaml.example:545`). Do not list it among AI-gateway plugins.

---

## 15. Open items / unverified

- Whether `auth: {}` (empty) passes ai-proxy schema validation at runtime for keyless local backends — not executed; use a dummy header.
- Aliyun endpoint host and Azure URL shapes in examples are placeholders.
- Online pages other than ai-proxy were not fetched; repo docs are the 3.19 branch and were used instead.
