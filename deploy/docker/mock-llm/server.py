"""Minimal OpenAI-compatible chat server for proving AI routes locally.

POST /v1/chat/completions echoes the last user message and reports token
usage so ai-rate-limiting has numbers to count. GET /v1/models lists one model.
shortcut: no streaming, no embeddings; swap in Ollama/LocalAI for real answers.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/v1/models":
            return self._send(200, {"object": "list", "data": [{"id": "mock", "object": "model"}]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self._send(404, {"error": "not found"})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)) or b"{}"))
        messages = body.get("messages", [])
        last = next((m.get("content", "") for m in reversed(messages) if m.get("role") == "user"), "")
        prompt_tokens = sum(len(str(m.get("content", "")).split()) for m in messages)
        reply = f"mock reply to: {last}"
        self._send(200, {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": body.get("model", "mock"),
            "choices": [{"index": 0, "finish_reason": "stop",
                         "message": {"role": "assistant", "content": reply}}],
            "usage": {"prompt_tokens": prompt_tokens,
                      "completion_tokens": len(reply.split()),
                      "total_tokens": prompt_tokens + len(reply.split())},
        })

    def log_message(self, fmt, *args):
        print(self.address_string(), fmt % args, flush=True)


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
