#!/bin/sh
# Same routes as apisix.yaml, applied through the Admin API (etcd mode, e.g.
# the deploy/docker stack or the Helm install). Needs APISIX_ADMIN_KEY and
# optionally APISIX_ADMIN_URL (default http://localhost:9180).
set -eu
: "${APISIX_ADMIN_KEY:?set APISIX_ADMIN_KEY}"
ADMIN=${APISIX_ADMIN_URL:-http://localhost:9180}/apisix/admin
LOCAL_LLM_ENDPOINT=${LOCAL_LLM_ENDPOINT:-http://mock-llm:8000/v1/chat/completions}
AZURE_ENDPOINT=${AZURE_ENDPOINT:-https://RESOURCE.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21}

put() { # put <path> <json>
  curl -sS -o /dev/null -w "$1 -> %{http_code}\n" -X PUT -H "X-API-KEY: $APISIX_ADMIN_KEY" "$ADMIN/$1" -d "$2"
}

put consumers/demo '{"username":"demo","plugins":{"key-auth":{"key":"$env://DEMO_CONSUMER_KEY"}}}'

put routes/local-chat '{
  "uri": "/local/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "ai-proxy": {"provider": "openai-compatible",
      "auth": {"header": {"Authorization": "Bearer $env://LOCAL_LLM_API_KEY"}},
      "options": {"model": "qwen-3.5-4b"},
      "override": {"endpoint": "'"$LOCAL_LLM_ENDPOINT"'"}},
    "ai-rate-limiting": {"limit": 20000, "time_window": 60, "limit_strategy": "total_tokens"}}}'

put routes/openai-chat '{
  "uri": "/openai/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "ai-proxy": {"provider": "openai",
      "auth": {"header": {"Authorization": "Bearer $env://OPENAI_API_KEY"}},
      "options": {"model": "gpt-4o-mini"}},
    "ai-prompt-guard": {"deny_patterns": ["(?i)ignore (all|any) previous instructions"]}}}'

put routes/anthropic-messages '{
  "uri": "/anthropic/v1/messages", "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "ai-proxy": {"provider": "anthropic",
      "auth": {"header": {"x-api-key": "$env://ANTHROPIC_API_KEY", "anthropic-version": "2023-06-01"}},
      "options": {"model": "claude-sonnet-4-5"}}}}'

put routes/azure-chat '{
  "uri": "/azure/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "ai-proxy": {"provider": "azure-openai",
      "auth": {"header": {"api-key": "$env://AZURE_OPENAI_API_KEY"}},
      "override": {"endpoint": "'"$AZURE_ENDPOINT"'"}}}}'

put routes/llm '{
  "uri": "/v1/chat/completions", "methods": ["POST"],
  "plugins": {
    "key-auth": {},
    "ai-prompt-decorator": {"prepend": [{"role": "system", "content": "You are a concise assistant."}]},
    "ai-proxy-multi": {
      "fallback_strategy": ["rate_limiting", "http_429", "http_5xx"], "max_retries": 1,
      "instances": [
        {"name": "azure", "provider": "azure-openai", "weight": 5,
         "auth": {"header": {"api-key": "$env://AZURE_OPENAI_API_KEY"}},
         "override": {"endpoint": "'"$AZURE_ENDPOINT"'"}},
        {"name": "openai", "provider": "openai", "weight": 3,
         "auth": {"header": {"Authorization": "Bearer $env://OPENAI_API_KEY"}},
         "options": {"model": "gpt-4o-mini"}},
        {"name": "anthropic", "provider": "anthropic", "weight": 2,
         "auth": {"header": {"x-api-key": "$env://ANTHROPIC_API_KEY", "anthropic-version": "2023-06-01"}},
         "options": {"model": "claude-sonnet-4-5"}}]},
    "ai-rate-limiting": {"limit_strategy": "total_tokens",
      "instances": [
        {"name": "azure", "limit": 100000, "time_window": 60},
        {"name": "openai", "limit": 50000, "time_window": 60},
        {"name": "anthropic", "limit": 50000, "time_window": 60}]}}}'
