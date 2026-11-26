"""Offline test harness: runs the pipeline against canned model responses.

Console output is ASCII-only; full detail goes to test-report.txt as UTF-8.
"""

import io
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ark import ArkClient, ArkError, strip_to_json
from pipeline import RecognitionPipeline, resolve_type

REPORT = []
RESULTS = []


class FakeClient:
    """Stands in for ArkClient. Charges a fixed token cost per call so the
    pipeline's usage accounting can be checked."""

    PROMPT_TOKENS = 800
    COMPLETION_TOKENS = 120

    def __init__(self, responses):
        self.queue = list(responses)
        self.calls = 0
        self.total_usage = {}

    def _charge(self):
        self.calls += 1
        self.total_usage["prompt_tokens"] = (
            self.total_usage.get("prompt_tokens", 0) + self.PROMPT_TOKENS)
        self.total_usage["completion_tokens"] = (
            self.total_usage.get("completion_tokens", 0) + self.COMPLETION_TOKENS)

    def _next(self):
        if not self.queue:
            raise AssertionError("FakeClient ran out of queued responses")
        item = self.queue.pop(0)
        if isinstance(item, Exception):
            raise item
        return item

    def complete_text(self, system, user, image_data_url=None, max_tokens=32,
                      temperature=0.0):
        self._charge()
        return self._next()

    def complete_json(self, system, user, image_data_url=None, max_tokens=1200,
                      temperature=0.0):
        self._charge()
        value = self._next()
        return strip_to_json(value) if isinstance(value, str) else value


def expect(condition, message):
    return [] if condition else [message]


TRAIN_OK = {"train_no": "G102", "depart_at": "2026-11-28T14:30:00",
            "from_station": "上海虹桥", "to_station": "北京南",
            "seat": "07车09F号", "seat_class": "二等座"}

CASES = []


def case(name, responses, checks, image=None, repair=True, expect_exc=None):
    CASES.append({
        "name": name,
        "responses": responses,
        "checks": checks,
        "image": image or name.encode("utf-8"),
        "repair": repair,
        "expect_exc": expect_exc,
    })


def chk_ok_true(r, c):
    return expect(r["ok"] is True, "expected ok=True, got errors=%r" % r["errors"])


def chk_calls(n):
    return lambda r, c: expect(r["model_calls"] == n,
                               "expected %d model calls, got %d" % (n, r["model_calls"]))


def chk_type(t):
    return lambda r, c: expect(r["type"] == t,
                               "expected type=%s, got %s" % (t, r["type"]))


def chk_field(key, value):
    return lambda r, c: expect(r["fields"].get(key) == value,
                               "field %s: expected %r, got %r"
                               % (key, value, r["fields"].get(key)))


def chk_no_field(key):
    return lambda r, c: expect(key not in r["fields"],
                               "field %s should have been dropped, got %r"
                               % (key, r["fields"].get(key)))


def chk_warning(substring):
    return lambda r, c: expect(
        any(substring in w for w in r["warnings"]),
        "expected a warning containing %r, got %r" % (substring, r["warnings"]))


def chk_error(substring):
    return lambda r, c: expect(
        any(substring in e for e in r["errors"]),
        "expected an error containing %r, got %r" % (substring, r["errors"]))


def chk_fallback(flag):
    return lambda r, c: expect(r["fallback_used"] is flag,
                               "expected fallback_used=%s" % flag)


def chk_tokens(calls):
    want = {"prompt_tokens": FakeClient.PROMPT_TOKENS * calls,
            "completion_tokens": FakeClient.COMPLETION_TOKENS * calls}
    return lambda r, c: expect(
        r["tokens"] == want,
        "expected %r tokens for %d calls, got %r" % (want, calls, r["tokens"]))


# --- happy paths, one per pass type -------------------------------------
case("train-happy", ["train", TRAIN_OK],
     [chk_ok_true, chk_calls(2), chk_type("train"), chk_field("train_no", "G102"),
      chk_tokens(2)])

case("flight-happy", ["flight", {"flight_no": "MU5101",
                                 "depart_at": "2026-12-01T08:05:00",
                                 "from_airport": "SHA", "to_airport": "PEK",
                                 "gate": "C12", "seat": "32A",
                                 "boarding_time": "2026-12-01T07:35:00"}],
     [chk_ok_true, chk_calls(2), chk_type("flight"),
      chk_field("flight_no", "MU5101")])

case("movie-happy", ["movie", {"title": "流浪地球3",
                               "start_at": "2026-11-29T19:20:00",
                               "cinema": "万达影城", "screen": "5厅",
                               "seat": "7排9、10座", "duration_min": "173"}],
     [chk_ok_true, chk_type("movie"), chk_field("title", "流浪地球3"),
      chk_field("duration_min", 173.0)])

case("parcel-happy", ["pickup_parcel", {"code": "8-3-2015", "carrier": "菜鸟",
                                        "station": "城东驿站",
                                        "expires_at": "2026-11-28"}],
     [chk_ok_true, chk_type("pickup_parcel"), chk_field("code", "8-3-2015"),
      chk_field("expires_at", "2026-11-28T00:00:00")])

case("food-pickup-happy", ["pickup_food", {"code": "A073",
                                           "store": "蜜雪冰城(人民广场店)"}],
     [chk_ok_true, chk_type("pickup_food"), chk_field("code", "A073")])

case("ride-happy", ["ride", {"plate_no": "沪AD12345", "platform": "滴滴出行",
                             "vehicle": "大众朗逸", "vehicle_color": "白色",
                             "pickup_point": "西藏中路地铁口"}],
     [chk_ok_true, chk_type("ride"), chk_field("plate_no", "沪AD12345")])

case("voucher-happy", ["voucher", {"code": "SN-2026-XYZ", "merchant": "Apple",
                                   "expires_at": "2026-12-31T23:59:59"}],
     [chk_ok_true, chk_type("voucher"), chk_field("code", "SN-2026-XYZ")])

case("subscription-happy", ["subscription", {"service": "爱奇艺黄金VIP",
                                             "price": "¥25.00",
                                             "cycle": "monthly",
                                             "next_charge_at": "2026-12-20"}],
     [chk_ok_true, chk_type("subscription"), chk_field("price", 25.0),
      chk_field("cycle", "monthly"),
      chk_field("next_charge_at", "2026-12-20T00:00:00")])

case("show-happy", ["show", {"title": "周杰伦嘉年华世界巡回",
                             "start_at": "2026-12-05T19:30:00",
                             "venue": "上海体育场", "price": 1280}],
     [chk_ok_true, chk_type("show"), chk_field("price", 1280.0)])

# --- classifier robustness ----------------------------------------------
case("classifier-chinese-label", ["火车票", TRAIN_OK],
     [chk_ok_true, chk_type("train"), chk_calls(2)])

case("classifier-prose-with-label", ["这看起来是一张火车票的截图", TRAIN_OK],
     [chk_ok_true, chk_type("train"), chk_calls(2)])

case("classifier-padded-identifier", ['  "train".  \n', TRAIN_OK],
     [chk_ok_true, chk_type("train")])

case("classifier-garbage-uses-fallback",
     ["完全看不出来这是什么图片", {"type": "train", "fields": TRAIN_OK}],
     [chk_ok_true, chk_type("train"), chk_fallback(True), chk_calls(2),
      chk_warning("unresolvable")])

case("fallback-invalid-triggers-typed-extract",
     ["看不出类型", {"type": "train", "fields": {"from_station": "上海虹桥"}},
      TRAIN_OK],
     [chk_ok_true, chk_type("train"), chk_calls(3), chk_fallback(True),
      chk_warning("retrying with the typed prompt"),
      chk_field("train_no", "G102")])

case("fallback-unparseable-is-fatal",
     ["无法判断", "not json at all"],
     [lambda r, c: expect(r["ok"] is False, "expected ok=False"),
      chk_type("unknown"), chk_calls(2), chk_error("no JSON object")])

case("fallback-without-type-becomes-unknown",
     ["无法判断", {"train_no": "K123", "depart_at": "2026-11-30T09:00:00"}],
     [chk_type("unknown"), chk_calls(2), chk_warning("did not declare a type")])

case("unknown-short-circuits", ["unknown"],
     [chk_type("unknown"), chk_calls(1), chk_tokens(1),
      lambda r, c: expect(r["fields"] == {}, "expected no fields")])

# --- malformed model output ---------------------------------------------
case("extract-markdown-fenced",
     ["movie", '```json\n{"title": "哪吒2", "start_at": "2026-11-27T20:00:00"}\n```'],
     [chk_ok_true, chk_type("movie"), chk_field("title", "哪吒2")])

case("extract-trailing-comma",
     ["voucher", '{"code": "ABC123", "merchant": "京东",}'],
     [chk_ok_true, chk_field("code", "ABC123")])

case("extract-prose-then-json",
     ["voucher", '好的，这是结果：\n{"code": "XYZ789"}\n希望有帮助'],
     [chk_ok_true, chk_field("code", "XYZ789")])

case("extract-non-object", ["train", "[1, 2, 3]"],
     [lambda r, c: expect(r["ok"] is False, "expected ok=False"),
      chk_calls(2), chk_error("expected a JSON object")])

# --- validation and repair ----------------------------------------------
case("missing-required-repair-fixes",
     ["train", {"from_station": "上海虹桥"}, TRAIN_OK],
     [chk_ok_true, chk_calls(3), chk_field("train_no", "G102")])

case("missing-required-repair-fails",
     ["train", {"from_station": "上海虹桥"}, {"from_station": "北京南"}],
     [lambda r, c: expect(r["ok"] is False, "expected ok=False"),
      chk_calls(3), chk_error("train_no"),
      chk_warning("did not improve")])

case("bad-enum-repair-fixes",
     ["subscription", {"service": "腾讯视频", "cycle": "biweekly"},
      {"service": "腾讯视频", "cycle": "monthly"}],
     [chk_ok_true, chk_calls(3), chk_field("cycle", "monthly")])

case("unparseable-datetime-no-repair",
     ["train", {"train_no": "G7", "depart_at": "11月28日下午两点半"}],
     [lambda r, c: expect(r["ok"] is False, "expected ok=False"),
      chk_calls(2), chk_error("depart_at")],
     repair=False)

case("chinese-datetime-normalised",
     ["train", {"train_no": "G7", "depart_at": "2026年11月28日 14:30"}],
     [chk_ok_true, chk_field("depart_at", "2026-11-28T14:30:00")])

case("unknown-fields-dropped",
     ["movie", {"title": "X", "start_at": "2026-11-27T20:00:00",
                "director": "郭帆", "douban_rating": 9.0}],
     [chk_ok_true, chk_no_field("director"), chk_no_field("douban_rating"),
      chk_warning("dropped unknown field")])

# --- transport failure ---------------------------------------------------
case("classifier-network-error-propagates",
     [ArkError("network: timed out")], [], expect_exc=ArkError)


def run():
    cache_dir = tempfile.mkdtemp(prefix="floato-cache-")
    passed = failed = 0
    total_calls = 0

    for spec in CASES:
        client = FakeClient(spec["responses"])
        pipe = RecognitionPipeline(client, cache_dir=cache_dir,
                                   repair=spec["repair"])
        problems = []
        result = None
        try:
            result = pipe.recognize(spec["image"])
            if spec["expect_exc"] is not None:
                problems.append("expected %s to be raised, nothing was"
                                % spec["expect_exc"].__name__)
        except Exception as exc:
            if spec["expect_exc"] is not None and isinstance(exc, spec["expect_exc"]):
                pass
            else:
                problems.append("unexpected %s: %s" % (type(exc).__name__, exc))

        if result is not None:
            total_calls += result["model_calls"]
            for check in spec["checks"]:
                try:
                    problems.extend(check(result, client))
                except Exception as exc:
                    problems.append("check %s blew up: %s"
                                    % (getattr(check, "__name__", check), exc))
            REPORT.append({"name": spec["name"], "result": result,
                           "problems": problems})
        else:
            REPORT.append({"name": spec["name"], "result": None,
                           "problems": problems})

        if problems:
            failed += 1
            print("FAIL  %-38s %s" % (spec["name"], problems[0][:100]))
        else:
            passed += 1
            print("ok    %-38s calls=%d" % (spec["name"],
                                             result["model_calls"] if result else 0))

    # cache behaviour, measured separately
    client = FakeClient(["train", TRAIN_OK])
    pipe = RecognitionPipeline(client, cache_dir=cache_dir)
    image = b"cache-probe-image"
    first = pipe.recognize(image)
    calls_after_first = client.calls
    second = pipe.recognize(image)
    cache_problems = []
    cache_problems += expect(first["cache_hit"] is False, "first call should miss cache")
    cache_problems += expect(second["cache_hit"] is True, "second call should hit cache")
    cache_problems += expect(client.calls == calls_after_first,
                             "cache hit made %d extra model calls"
                             % (client.calls - calls_after_first))
    cache_problems += expect(second["fields"].get("train_no") == "G102",
                             "cached payload lost fields")
    cache_problems += expect(second["tokens"] == {} and second["elapsed_ms"] == 0,
                             "cache hit reported usage: tokens=%r elapsed=%r"
                             % (second["tokens"], second["elapsed_ms"]))
    total_calls += calls_after_first
    if cache_problems:
        failed += 1
        print("FAIL  %-38s %s" % ("cache-hit", cache_problems[0][:100]))
    else:
        passed += 1
        print("ok    %-38s calls=%d (2nd call: 0)" % ("cache-hit", calls_after_first))
    REPORT.append({"name": "cache-hit", "result": second, "problems": cache_problems})

    # failed results must not be cached
    client = FakeClient(["train", {"from_station": "上海虹桥"}] * 2)
    pipe = RecognitionPipeline(client, cache_dir=cache_dir, repair=False)
    bad = pipe.recognize(b"uncacheable-broken-image")
    calls_after_first = client.calls
    bad_cached = pipe.recognize(b"uncacheable-broken-image")
    nocache_problems = expect(bad_cached["cache_hit"] is False,
                              "an invalid result was served from cache")
    nocache_problems += expect(
        client.calls == calls_after_first + 2,
        "expected a second full recognition run, calls went %d -> %d"
        % (calls_after_first, client.calls))
    total_calls += client.calls
    if nocache_problems:
        failed += 1
        print("FAIL  %-38s %s" % ("invalid-not-cached", nocache_problems[0][:100]))
    else:
        passed += 1
        print("ok    %-38s calls=%d" % ("invalid-not-cached", client.calls))
    REPORT.append({"name": "invalid-not-cached", "result": bad,
                   "problems": nocache_problems})

    shutil.rmtree(cache_dir, ignore_errors=True)

    print("\n%d cases: %d passed, %d failed | %d model calls exercised"
          % (passed + failed, passed, failed, total_calls))

    with io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "test-report.txt"), "w", encoding="utf-8") as out:
        for entry in REPORT:
            out.write("=" * 72 + "\n")
            out.write("CASE %s\n" % entry["name"])
            if entry["problems"]:
                out.write("  PROBLEMS:\n")
                for problem in entry["problems"]:
                    out.write("    - %s\n" % problem)
            if entry["result"] is not None:
                out.write("  RESULT:\n")
                for key in ("type", "type_label", "ok", "model_calls",
                            "tokens", "elapsed_ms", "cache_hit",
                            "fallback_used"):
                    out.write("    %-14s %r\n" % (key, entry["result"].get(key)))
                out.write("    fields        %r\n" % entry["result"].get("fields"))
                out.write("    errors        %r\n" % entry["result"].get("errors"))
                out.write("    warnings      %r\n" % entry["result"].get("warnings"))
            else:
                out.write("  (no result object)\n")
    return 1 if failed else 0


def selftest_resolve_type():
    probes = [
        ("train", "train"), ("Train", "train"), ("  train\n", "train"),
        ("火车票", "train"), ("这是一张火车票", "train"),
        ('"movie".', "movie"), ("unknown", "unknown"),
        ("以上都不是", "unknown"), ("", None), ("zzz", None),
        ("pickup_parcel", "pickup_parcel"), ("快递取件码", "pickup_parcel"),
        ("subscription", "subscription"), ("订阅与账单", "subscription"),
    ]
    bad = [(raw, want, resolve_type(raw)) for raw, want in probes
           if resolve_type(raw) != want]
    print("\nresolve_type probe: %d/%d correct" % (len(probes) - len(bad), len(probes)))
    for raw, want, got in bad:
        print("  MISMATCH %r -> want %r got %r" % (raw, want, got))
    return 1 if bad else 0


def selftest_strip_to_json():
    probes = [
        ('{"a": 1}', {"a": 1}),
        ('```json\n{"a": 1}\n```', {"a": 1}),
        ('结果：{"a": 1} 完毕', {"a": 1}),
        ('{"a": 1,}', {"a": 1}),
        ('{"a": {"b": 2},}', {"a": {"b": 2}}),
    ]
    bad = []
    for raw, want in probes:
        try:
            got = strip_to_json(raw)
        except ArkError as exc:
            got = "ERR:%s" % exc
        if got != want:
            bad.append((raw, want, got))
    failures = 0
    for raw in ("not json at all", "[1,2,3]"):
        try:
            strip_to_json(raw)
            bad.append((raw, "ArkError", "no exception"))
            failures += 1
        except ArkError:
            pass
    print("strip_to_json probe: %d/%d correct"
          % (len(probes) + 2 - len(bad), len(probes) + 2))
    for raw, want, got in bad:
        print("  MISMATCH %r -> want %r got %r" % (raw, want, got))
    return 1 if bad else 0


def selftest_config():
    """ARK_API_KEY and ARK_MODEL must both be required, with actionable messages."""
    problems = []
    saved = {k: os.environ.pop(k, None) for k in ("ARK_API_KEY", "ARK_MODEL")}
    try:
        try:
            ArkClient()
            problems.append("ArkClient() started without ARK_API_KEY")
        except ArkError as exc:
            if "ARK_API_KEY" not in str(exc):
                problems.append("missing-key message does not name ARK_API_KEY")

        os.environ["ARK_API_KEY"] = "ark-test-key"
        try:
            ArkClient()
            problems.append("ArkClient() started without ARK_MODEL")
        except ArkError as exc:
            if "ARK_MODEL" not in str(exc):
                problems.append("missing-model message does not name ARK_MODEL")

        client = ArkClient(model="ep-test-endpoint-123")
        payload = client._payload("sys", "usr", "data:image/png;base64,AAA",
                                  100, 0.0)
        problems += expect(payload["model"] == "ep-test-endpoint-123",
                           "model not wired into the request payload")
        content = payload["messages"][1]["content"]
        problems += expect(content[0]["type"] == "image_url",
                           "image must be the first content part")
        problems += expect(content[1] == {"type": "text", "text": "usr"},
                           "text part malformed")
        problems += expect(payload["messages"][0]["role"] == "system",
                           "system message missing")
        problems += expect(
            payload["messages"][0]["content"] == "sys",
            "system content malformed")
    finally:
        for key, value in saved.items():
            os.environ.pop(key, None)
            if value is not None:
                os.environ[key] = value

    print("ark config probe: %s" % ("OK" if not problems else "FAILED"))
    for problem in problems:
        print("  - %s" % problem)
    return 1 if problems else 0


if __name__ == "__main__":
    exit_code = 0
    exit_code |= selftest_config()
    exit_code |= selftest_resolve_type()
    exit_code |= selftest_strip_to_json()
    print()
    exit_code |= run()
    sys.exit(exit_code)
