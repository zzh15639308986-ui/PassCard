"""Minimal HTTP front end for the recognition pipeline. Stdlib only.

    py server.py                    # 127.0.0.1:8787, this machine only
    py server.py --host 0.0.0.0     # reachable from a phone on the same Wi-Fi
    py server.py --host 0.0.0.0 --env-file "$HOME/ark.env"

--env-file takes KEY=VALUE lines from a file kept outside the repository, so
the Ark key never has to be exported by hand or pasted into a chat.

Set PASSCARD_TOKEN to require `Authorization: Bearer <token>` on every
request. Without it the endpoint is open, which is acceptable on a
trusted LAN and never acceptable on a public address.
"""

import argparse
import base64
import binascii
import json
import os
import socket
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from ark import ArkClient, ArkError, load_env_file
from pipeline import RecognitionPipeline

CACHE_DIR = os.environ.get("FLOATO_CACHE_DIR",
                           os.path.join(os.path.dirname(__file__), ".cache"))
PIPELINE = None
AUTH_TOKEN = os.environ.get("PASSCARD_TOKEN", "")


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

    def _authorized(self):
        if not AUTH_TOKEN:
            return True
        return self.headers.get("Authorization", "") == "Bearer " + AUTH_TOKEN

    def _fail(self, exc):
        # An uncaught exception kills the handler thread and the socket
        # closes with no response at all; iOS renders that as "network
        # connection lost" with nothing to diagnose. Always answer, always log.
        traceback.print_exc()
        return self._send(500, {"error": "internal: %s" % exc})

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._authorized():
            return self._send(401, {"error": "missing or bad token"})
        if self.path == "/healthz":
            try:
                pipeline = build_pipeline()
                return self._send(200, {"ok": True,
                                        "model": pipeline.client.model,
                                        "endpoint": pipeline.client.endpoint,
                                        "cache_dir": CACHE_DIR})
            except Exception as exc:
                return self._fail(exc)
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return self._send(401, {"error": "missing or bad token"})
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
        except Exception as exc:
            return self._fail(exc)
        return self._send(200 if result["ok"] else 422, result)

    def log_message(self, fmt, *args):
        sys.stderr.write("[server] " + fmt % args + "\n")


def lan_ipv4():
    """The address a phone on the same Wi-Fi must dial.

    connect() on a UDP socket sends no packets; it only makes the kernel pick
    the source address it would use for that destination, which is the
    interface facing the default route. gethostname() is not enough: on a
    multi-homed machine it happily returns a virtual adapter's address.
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 53))
        return probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()


def main():
    parser = argparse.ArgumentParser(description="PassCard recognition backend")
    parser.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"),
                        help="127.0.0.1 keeps this machine-only; 0.0.0.0 lets a "
                             "phone on the same network reach it")
    parser.add_argument("--port", type=int,
                        default=int(os.environ.get("PORT", 8787)))
    parser.add_argument("--env-file",
                        help="KEY=VALUE file outside the repository holding "
                             "ARK_API_KEY and ARK_MODEL; the environment wins")
    args = parser.parse_args()

    if args.env_file:
        try:
            loaded = load_env_file(args.env_file)
        except OSError as exc:
            print("cannot read --env-file: %s" % exc, file=sys.stderr)
            return 1
        print("env-file provided: %s" % (", ".join(loaded) or "nothing new"),
              flush=True)

    try:
        build_pipeline()
    except ArkError as exc:
        print("startup failed: %s" % exc, file=sys.stderr)
        return 1
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    # flush: stdout is block-buffered once redirected, so without this a
    # nohup/log-file run shows no address at all until the server exits.
    print("listening on http://%s:%d  (POST /recognize, GET /healthz)"
          % (args.host, args.port), flush=True)

    if AUTH_TOKEN:
        print("token auth enabled (PASSCARD_TOKEN)", flush=True)
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        lan = lan_ipv4()
        if lan:
            print("in the app, set the backend to:  http://%s:%d"
                  % (lan, args.port), flush=True)
        if not AUTH_TOKEN:
            print("WARNING: this endpoint has no authentication, and every request")
            print("spends your Ark quota. Only expose it on a network you trust,")
            print("and stop the server when you are done.")
        print("If the phone cannot connect, allow the port from an ADMIN prompt:")
        print('  netsh advfirewall firewall add rule name="PassCard backend"'
              " dir=in action=allow protocol=TCP localport=%d" % args.port,
              flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
