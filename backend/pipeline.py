"""Two-stage recognition pipeline: classify -> extract -> validate -> normalise."""

import hashlib
import json
import os
import time

import prompts
from ark import ArkError, encode_image
from passes import PASS_TYPES, SPEC, TYPE_LABELS, normalise_fields, validate

UNKNOWN = "unknown"


def resolve_type(raw):
    """Models rarely emit a bare identifier. Map whatever came back onto a type."""
    if not isinstance(raw, str):
        return None
    text = raw.strip().lower().strip("\"'`。.，,：: \n\t")
    if not text:
        return None
    if text in PASS_TYPES:
        return text
    if text == UNKNOWN or "都不是" in text or "没有凭证" in text:
        return UNKNOWN
    for candidate in PASS_TYPES:
        if candidate in text:
            return candidate
    for candidate, label in TYPE_LABELS.items():
        if label.lower() in text:
            return candidate
    return None


def unwrap(raw):
    """Accept both {fields...} and {type, fields} shapes."""
    if not isinstance(raw, dict):
        raise ArkError("model returned %s, expected object" % type(raw).__name__)
    if "fields" in raw and isinstance(raw["fields"], dict):
        declared = resolve_type(str(raw.get("type", "")))
        return declared, raw["fields"]
    return None, raw


class RecognitionPipeline:
    def __init__(self, client, cache_dir=None, cache_ttl=86400, repair=True):
        self.client = client
        self.cache_dir = cache_dir
        self.cache_ttl = cache_ttl
        self.repair = repair

    def _cache_path(self, digest):
        if not self.cache_dir:
            return None
        return os.path.join(self.cache_dir, digest + ".json")

    def _cache_get(self, digest):
        path = self._cache_path(digest)
        if not path or not os.path.exists(path):
            return None
        if time.time() - os.path.getmtime(path) > self.cache_ttl:
            return None
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)

    def _cache_put(self, digest, result):
        path = self._cache_path(digest)
        if not path:
            return
        os.makedirs(self.cache_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False)

    def recognize(self, image_bytes, mime="image/jpeg"):
        digest = hashlib.sha256(image_bytes).hexdigest()
        cached = self._cache_get(digest)
        if cached is not None:
            cached = dict(cached)
            cached["cache_hit"] = True
            cached["model_calls"] = 0
            cached["tokens"] = {}
            cached["elapsed_ms"] = 0
            return cached

        started = time.perf_counter()
        snapshot = (getattr(self.client, "calls", 0),
                    dict(getattr(self.client, "total_usage", {}) or {}))
        data_url = encode_image(image_bytes, mime)
        fallback_used = False
        fields = None
        warnings = []

        pass_type = resolve_type(self.client.complete_text(
            prompts.CLASSIFY_SYSTEM, prompts.CLASSIFY_USER, data_url,
            max_tokens=16))

        if pass_type is None:
            fallback_used = True
            warnings.append("classifier output unresolvable, used fallback prompt")
            try:
                declared, fields = unwrap(self.client.complete_json(
                    prompts.FALLBACK_SYSTEM, prompts.FALLBACK_USER, data_url))
            except ArkError as exc:
                return self._finish(digest, UNKNOWN, {}, [str(exc)], warnings,
                                    started, snapshot, fallback_used,
                                    fatal=True)
            pass_type = declared or UNKNOWN
            if declared is None:
                warnings.append("fallback did not declare a type")

        if pass_type == UNKNOWN:
            return self._finish(digest, UNKNOWN, {}, [], warnings, started,
                                snapshot, fallback_used)

        if pass_type not in SPEC:
            warnings.append("type %r is not in catalogue, treating as unknown"
                            % pass_type)
            return self._finish(digest, UNKNOWN, {}, [], warnings, started,
                                snapshot, fallback_used)

        if fields is not None:
            if not validate(pass_type, fields):
                return self._finish(digest, pass_type, fields, [], warnings,
                                    started, snapshot, fallback_used)
            warnings.append("fallback result failed validation, "
                            "retrying with the typed prompt")
            fields = None

        try:
            _, fields = unwrap(self.client.complete_json(
                prompts.extract_system(pass_type),
                prompts.extract_user(pass_type), data_url))
        except ArkError as exc:
            return self._finish(digest, pass_type, {}, [str(exc)], warnings,
                                started, snapshot, fallback_used, fatal=True)

        errors = validate(pass_type, fields)
        if errors and self.repair:
            try:
                _, repaired = unwrap(self.client.complete_json(
                    prompts.extract_system(pass_type),
                    prompts.repair_user(pass_type, errors), data_url))
                new_errors = validate(pass_type, repaired)
                if len(new_errors) < len(errors):
                    fields, errors = repaired, new_errors
                else:
                    warnings.append("repair attempt did not improve result")
            except ArkError as exc:
                warnings.append("repair failed: %s" % exc)

        return self._finish(digest, pass_type, fields, errors, warnings, started,
                            snapshot, fallback_used)

    def _finish(self, digest, pass_type, fields, errors, warnings, started,
                snapshot, fallback_used, fatal=False):
        if not fatal and pass_type in SPEC:
            fields, norm_warnings = normalise_fields(pass_type, fields)
            warnings.extend(norm_warnings)
        calls_before, usage_before = snapshot
        usage_now = getattr(self.client, "total_usage", {}) or {}
        tokens = {key: usage_now.get(key, 0) - usage_before.get(key, 0)
                  for key in set(usage_now) | set(usage_before)}
        result = {
            "type": pass_type,
            "type_label": TYPE_LABELS.get(pass_type, "未识别"),
            "fields": fields,
            "errors": errors,
            "warnings": warnings,
            "fallback_used": fallback_used,
            "image_sha256": digest,
            "model_calls": max(getattr(self.client, "calls", 0) - calls_before, 0),
            "tokens": {k: v for k, v in sorted(tokens.items()) if v},
            "elapsed_ms": int((time.perf_counter() - started) * 1000),
            "cache_hit": False,
            "ok": not errors and not fatal,
        }
        if result["ok"]:
            self._cache_put(digest, result)
        return result
