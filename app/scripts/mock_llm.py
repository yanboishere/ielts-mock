#!/usr/bin/python3 -I
"""Local stand-in for the Claude Messages API and OpenAI Chat Completions, for testing the app's AI code paths.

  scripts/mock_llm.py [port]        (default 8787)

Logs every request body to /tmp/mock_llm/NNN-<path>.json and streams back a JSON object generated from the
request's JSON schema (Claude: output_config.format.schema, OpenAI: response_format.json_schema.schema).
"""
import json, os, sys, itertools
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = "/tmp/mock_llm"
os.makedirs(LOG, exist_ok=True)
counter = itertools.count(1)


def sample(schema, name=""):
    t = schema.get("type")
    if isinstance(t, list):
        t = next((x for x in t if x != "null"), "string")
    if "enum" in schema:
        return schema["enum"][0]
    if t == "object":
        return {k: sample(v, k) for k, v in schema.get("properties", {}).items()}
    if t == "array":
        n = max(schema.get("minItems", 1), 2)
        return [sample(schema.get("items", {}), name) for _ in range(n)]
    if t == "integer":
        return schema.get("minimum", 7)
    if t == "number":
        lo, hi = schema.get("minimum", 0), schema.get("maximum", 9)
        return 6.5 if lo <= 6.5 <= hi else lo
    if t == "boolean":
        return True
    return f"示例{name}：这是模拟服务器生成的内容。"


def fill_question_numbers(obj, prompt_text):
    """Explanations are matched to questions by number; reuse the numbers mentioned in the prompt."""
    import re
    nums = [int(n) for n in re.findall(r'"(?:number|question|q)"\s*:\s*(\d+)', prompt_text)]
    if not nums:
        nums = [int(n) for n in re.findall(r"\bQ(\d{1,2})\b", prompt_text)]
    seen = []
    for n in nums:
        if n not in seen:
            seen.append(n)
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, list) and v and isinstance(v[0], dict) and any(x in v[0] for x in ("number", "question", "q")) and seen:
                    tmpl = v[0]
                    o[k] = []
                    for n in seen:
                        item = json.loads(json.dumps(tmpl))
                        for key in ("number", "question", "q"):
                            if key in item and isinstance(item[key], int):
                                item[key] = n
                        o[k].append(item)
                else:
                    walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)
    walk(obj)
    return obj


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        req = json.loads(body)
        i = next(counter)
        tag = "claude" if self.path.endswith("/messages") else "openai"
        with open(f"{LOG}/{i:03d}-{tag}.json", "w") as f:
            json.dump({"path": self.path, "headers": {k: (v if k.lower() not in ("x-api-key", "authorization") else "<redacted>") for k, v in self.headers.items()}, "body": req}, f, ensure_ascii=False, indent=1)
        text_in = json.dumps(req, ensure_ascii=False)
        if tag == "claude":
            schema = (req.get("output_config") or {}).get("format", {}).get("schema", {"type": "object", "properties": {}})
        else:
            schema = (req.get("response_format") or {}).get("json_schema", {}).get("schema", {"type": "object", "properties": {}})
        out = json.dumps(fill_question_numbers(sample(schema), text_in), ensure_ascii=False)
        chunks = [out[j:j + 40] for j in range(0, len(out), 40)]
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()

        def send(obj, event=None):
            s = (f"event: {event}\n" if event else "") + "data: " + json.dumps(obj, ensure_ascii=False) + "\n\n"
            self.wfile.write(s.encode())
            self.wfile.flush()

        if tag == "claude":
            send({"type": "message_start", "message": {"model": req["model"], "usage": {"input_tokens": len(text_in) // 4}}}, "message_start")
            send({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, "content_block_start")
            for c in chunks:
                send({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": c}}, "content_block_delta")
            send({"type": "content_block_stop", "index": 0}, "content_block_stop")
            send({"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": len(out) // 4}}, "message_delta")
            send({"type": "message_stop"}, "message_stop")
        else:
            for c in chunks:
                send({"model": req["model"], "choices": [{"index": 0, "delta": {"content": c}, "finish_reason": None}]})
            send({"model": req["model"], "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 10, "completion_tokens": 10}})
            self.wfile.write(b"data: [DONE]\n\n")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
