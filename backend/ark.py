"""Volcano Engine Ark (Doubao) vision client. OpenAI-compatible chat completions."""

import base64
import json
import os
import re
import time
import urllib.error
import urllib.request

DEFAULT_ENDPOINT = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"

MODEL_HINT = (
    "ARK_MODEL is not set. Get it from console.volcengine.com/ark -> Online "
    "Inference: either a Model ID such as doubao-seed-1-6-vision-... or an "
    "endpoint ID such as ep-.... Then export it as ARK_MODEL."
)

_FENCE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.IGNORECASE)
_TRAILING_COMMA = re.compile(r",(\s*[}\]])")


class ArkError(RuntimeError):
    pass


def strip_to_json(text):
    """LLMs wrap JSON in fences or prose. Peel that off and parse."""
    if not isinstance(text, str):
        raise ArkError("model returned non-string: %r" % type(text).__name__)
    candidate = _FENCE.sub("", text.strip())
    parsed = None
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError:
        start, end = candidate.find("{"), candidate.rfind("}")
        if start == -1 or end <= start:
            raise ArkError("no JSON object in model output: %.200r" % text)
        candidate = candidate[start:end + 1]
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            try:
                parsed = json.loads(_TRAILING_COMMA.sub(r"\1", candidate))
            except json.JSONDecodeError as exc:
                raise ArkError("unparseable JSON from model: %s" % exc)
    if not isinstance(parsed, dict):
        raise ArkError("expected a JSON object, got %s"
                       % type(parsed).__name__)
    return parsed


def encode_image(image_bytes, mime="image/jpeg"):
    return "data:%s;base64,%s" % (mime, base64.b64encode(image_bytes).decode())


class ArkClient:
    def __init__(self, api_key=None, model=None, endpoint=None, timeout=45,
                 retries=2, backoff=1.5, thinking=None):
        self.api_key = api_key or os.environ.get("ARK_API_KEY")
        if not self.api_key:
            raise ArkError(
                "ARK_API_KEY is not set. Export your Volcano Ark API key first.")
        self.model = model or os.environ.get("ARK_MODEL")
        if not self.model:
            raise ArkError(MODEL_HINT)
        self.endpoint = endpoint or os.environ.get("ARK_ENDPOINT") or DEFAULT_ENDPOINT
        self.timeout = timeout
        self.retries = retries
        self.backoff = backoff
        # Seed 2.1 reasons by default and bills the reasoning as output tokens;
        # {"type": "disabled"} cuts both latency and cost on extraction tasks.
        self.thinking = thinking
        self.calls = 0
        self.total_usage = {}

    def _post(self, payload):
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint, data=body, method="POST",
            headers={"Content-Type": "application/json",
                     "Authorization": "Bearer %s" % self.api_key})
        last = None
        for attempt in range(self.retries + 1):
            self.calls += 1
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")[:400]
                last = ArkError("HTTP %s: %s" % (exc.code, detail))
                if exc.code < 500 and exc.code != 429:
                    raise last
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last = ArkError("network: %s" % exc)
            if attempt < self.retries:
                time.sleep(self.backoff ** attempt)
        raise last

    def _content(self, data):
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            raise ArkError("malformed Ark response: %.300r" % data)

    def _accumulate(self, data):
        usage = data.get("usage") or {}
        for key, value in usage.items():
            try:
                self.total_usage[key] = self.total_usage.get(key, 0) + int(value)
            except (TypeError, ValueError):
                continue

    def complete_text(self, system, user, image_data_url=None, max_tokens=32,
                      temperature=0.0):
        payload = self._payload(system, user, image_data_url, max_tokens, temperature)
        data = self._post(payload)
        self._accumulate(data)
        return self._content(data).strip()

    def complete_json(self, system, user, image_data_url=None, max_tokens=1200,
                      temperature=0.0):
        payload = self._payload(system, user, image_data_url, max_tokens, temperature)
        data = self._post(payload)
        self._accumulate(data)
        return strip_to_json(self._content(data))

    def _payload(self, system, user, image_data_url, max_tokens, temperature):
        content = []
        if image_data_url:
            content.append({"type": "image_url",
                            "image_url": {"url": image_data_url}})
        content.append({"type": "text", "text": user})
        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": content}],
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if self.thinking:
            payload["thinking"] = self.thinking
        return payload
