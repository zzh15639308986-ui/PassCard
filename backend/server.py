"""Minimal HTTP front end for the recognition pipeline. Stdlib only."""

import base64
import binascii
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from ark import ArkClient, ArkError
from pipeline import RecognitionPipeline

CACHE_DIR = os.environ.get("FLOATO_CACHE_DIR",
                           os.path.join(os.path.dirname(__file__), ".cache"))
PIPELINE = None


def build_pipeline():
    global PIPELINE
    if PIPELINE is None:
        # Seed 2.1 reasons by default and bills that reasoning as output
        # tokens. On the same 8 fixtures, thinking on measured 27.4s and
        # 0.0078 CNY per image against 2.6s and 0.0025 CNY with it off, at
        # identical type accuracy. Off is the default, not an optimisation.
        PIPELINE = RecognitionPipeline(
            ArkClient(thinking={"type": "disabled"}), cache_dir=CACHE_DIR)
    return PIPELINE


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            pipeline = build_pipeline()
            return self._send(200, {"ok": True,
                                    "model": pipeline.client.model,
                                    "endpoint": pipeline.client.endpoint,
                                    "cache_dir": CACHE_DIR})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/recognize":
            return self._send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return self._send(400, {"error": "bad Content-Length"})
        raw = self.rfile.read(length)

        content_type = self.headers.get("Content-Type", "")
        if content_type.startswith("application/json"):
            try:
                payload = json.loads(raw.decode("utf-8"))
                image = base64.b64decode(payload["image_b64"])
                mime = payload.get("mime", "image/jpeg")
            except (json.JSONDecodeError, KeyError, binascii.Error,
                    UnicodeDecodeError) as exc:
                return self._send(400, {"error": "bad request: %s" % exc})
        else:
            image, mime = raw, content_type or "image/jpeg"

        if not image:
            return self._send(400, {"error": "empty image"})

        try:
            result = build_pipeline().recognize(image, mime)
        except ArkError as exc:
            return self._send(502, {"error": str(exc)})
        return self._send(200 if result["ok"] else 422, result)

    def log_message(self, fmt, *args):
        sys.stderr.write("[server] " + fmt % args + "\n")


def main():
    port = int(os.environ.get("PORT", 8787))
    try:
        build_pipeline()
    except ArkError as exc:
        print("startup failed: %s" % exc, file=sys.stderr)
        return 1
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("listening on http://127.0.0.1:%d  (POST /recognize, GET /healthz)" % port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
