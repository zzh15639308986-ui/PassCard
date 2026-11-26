"""Measure recognition accuracy, latency and token cost on real screenshots.

    py measure.py IMG [IMG ...] [--labels labels.json] [--out report.json]
                  [--env-file PATH] [--no-think] [--keep-cache]
                  [--price-in CNY_PER_MILLION] [--price-out CNY_PER_MILLION]

Needs ARK_API_KEY and ARK_MODEL. --env-file reads KEY=VALUE lines from a file
outside the repository so the key never has to pass through a chat transcript
and never lands in version control.

--no-think sends thinking={"type": "disabled"}. Seed 2.1 reasons by default
and bills that reasoning as output tokens: on the same 8 synthetic fixtures,
thinking on measured 27.4s mean latency and 0.0078 CNY per image versus 2.6s
and 0.0025 CNY with it off, at identical type accuracy. Treat off as the
default for extraction work, not as an optimisation.

Nothing secret is ever printed. The console gets ASCII only, because this
machine's codepage mangles Chinese; the labels and warnings go to the report
file as UTF-8 instead.
"""

import argparse
import json
import mimetypes
import os
import shutil
import statistics
import sys
import tempfile
import time

from ark import ArkClient, ArkError, load_env_file
from pipeline import RecognitionPipeline

SECRET_KEYS = ("ARK_API_KEY",)


def mime_for(path):
    guess = mimetypes.guess_type(path)[0]
    if guess in ("image/jpeg", "image/png", "image/webp", "image/heic"):
        return guess
    ext = os.path.splitext(path)[1].lower()
    return {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
            ".webp": "image/webp", ".heic": "image/heic"}.get(ext, "image/jpeg")


def token_parts(tokens):
    """Ark reports total_tokens next to its parts, and ark.py passes every key
    through. Counting both would double the bill, so mirror the client: trust
    the reported total, else add the parts."""
    if "total_tokens" in tokens:
        return tokens.get("prompt_tokens", 0), tokens.get("completion_tokens", 0), tokens["total_tokens"]
    prompt = tokens.get("prompt_tokens", 0)
    completion = tokens.get("completion_tokens", 0)
    return prompt, completion, prompt + completion


def percentile(values, pct):
    if not values:
        return 0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(round(pct / 100.0 * (len(ordered) - 1)))))
    return ordered[index]


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("images", nargs="+")
    parser.add_argument("--labels", help="JSON object mapping filename to expected type")
    parser.add_argument("--out", default="measure-report.json")
    parser.add_argument("--env-file")
    parser.add_argument("--price-in", type=float, help="CNY per million input tokens")
    parser.add_argument("--price-out", type=float, help="CNY per million output tokens")
    parser.add_argument("--keep-cache", action="store_true")
    parser.add_argument("--no-think", action="store_true",
                        help="send thinking={type: disabled}; Seed 2.1 reasons by "
                             "default and bills reasoning as output tokens")
    args = parser.parse_args()

    if args.env_file:
        loaded = load_env_file(args.env_file)
        print("env-file provided: %s" % (", ".join(loaded) or "nothing new"))

    missing = [k for k in ("ARK_API_KEY", "ARK_MODEL") if not os.environ.get(k)]
    if missing:
        print("MISSING: %s" % ", ".join(missing))
        print("Set them in the environment or pass --env-file.")
        return 2
    key = os.environ["ARK_API_KEY"]
    print("ARK_API_KEY: set, len=%d prefix=%s... (value not printed)" % (len(key), key[:4]))
    print("ARK_MODEL: %s" % os.environ["ARK_MODEL"])
    print("thinking: %s" % ("disabled" if args.no_think else "model default"))

    labels = {}
    if args.labels:
        with open(args.labels, "r", encoding="utf-8") as handle:
            labels = {os.path.basename(k).lower(): v for k, v in json.load(handle).items()}
        print("labels loaded for %d files" % len(labels))

    # A shared cache would turn the second run of the same screenshot into a
    # free cache hit and quietly halve the measured cost, so each run starts
    # from an empty one unless the caller explicitly asks otherwise.
    cache_dir = args.keep_cache and os.path.join(tempfile.gettempdir(), "passcard-measure-cache") \
        or tempfile.mkdtemp(prefix="passcard-measure-")
    print("cache dir: %s" % cache_dir)

    client = ArkClient(thinking={"type": "disabled"} if args.no_think else None)
    # Ark's model catalogue is global but activation is per account, so a valid
    # key can still 404 ModelNotOpen on every call. One 1-token ping costs
    # nothing and turns an 8-image run of identical failures into one line.
    try:
        client.complete_text("ping", "reply with the single word ok", max_tokens=4)
    except ArkError as exc:
        print("preflight failed: %r rejected a 1-token ping: %.300s"
              % (client.model, exc))
        if "ModelNotOpen" in str(exc):
            print("the account has not activated this model. Activate it in the Ark")
            print("console, or point ARK_MODEL at an inference endpoint id (ep-...).")
        print("nothing was measured: no images were sent and no tokens billed")
        return 2
    pipeline = RecognitionPipeline(client, cache_dir=cache_dir)

    rows = []
    for index, path in enumerate(args.images, 1):
        name = os.path.basename(path)
        row = {"file": name, "path": path}
        if not os.path.isfile(path):
            row.update(ok=False, error="file not found")
            rows.append(row)
            print("[%d/%d] %s -> MISSING FILE" % (index, len(args.images), name))
            continue
        with open(path, "rb") as handle:
            blob = handle.read()
        row["bytes"] = len(blob)
        row["expected"] = labels.get(name.lower())
        wall_start = time.perf_counter()
        try:
            result = pipeline.recognize(blob, mime_for(path))
        except ArkError as exc:
            row.update(ok=False, error=str(exc))
            rows.append(row)
            print("[%d/%d] %s -> ArkError: %.200s" % (index, len(args.images), name, exc))
            continue
        except Exception as exc:
            row.update(ok=False, error="%s: %s" % (type(exc).__name__, exc))
            rows.append(row)
            print("[%d/%d] %s -> %s: %.200s"
                  % (index, len(args.images), name, type(exc).__name__, exc))
            continue
        row["wall_ms"] = int((time.perf_counter() - wall_start) * 1000)
        row["type"] = result["type"]
        row["type_label"] = result["type_label"]
        row["ok"] = result["ok"]
        row["model_calls"] = result["model_calls"]
        row["elapsed_ms"] = result["elapsed_ms"]
        row["cache_hit"] = result["cache_hit"]
        row["errors"] = result["errors"]
        row["warnings"] = result["warnings"]
        row["fields"] = result["fields"]
        prompt, completion, total = token_parts(result["tokens"])
        row["tokens"] = {"prompt": prompt, "completion": completion, "total": total}
        row["tokens_raw"] = result["tokens"]
        if row["expected"] is not None:
            row["type_correct"] = result["type"] == row["expected"]
        rows.append(row)
        verdict = "OK " if result["ok"] else "BAD"
        match = ""
        if row["expected"] is not None:
            match = " [%s]" % ("match" if row["type_correct"] else "MISMATCH want " + row["expected"])
        print("[%d/%d] %s -> %s %s type=%s calls=%d elapsed=%dms tokens=%d%s"
              % (index, len(args.images), name, verdict,
                 "CACHE-HIT" if result["cache_hit"] else "        ",
                 result["type"], result["model_calls"], result["elapsed_ms"],
                 total, match))

    done = [r for r in rows if "elapsed_ms" in r]
    graded = [r for r in done if r.get("expected") is not None]
    # A cache hit reports zero tokens and zero milliseconds, so folding it into
    # the averages would make a second run over the same folder look half the
    # price and instantly fast. Latency, tokens and cost describe paid calls
    # only; the cache-hit count is reported next to them.
    paid = [r for r in done if not r["cache_hit"]]
    summary = {
        "model": os.environ["ARK_MODEL"],
        "thinking_disabled": bool(args.no_think),
        "images_requested": len(args.images),
        "images_recognised": len(done),
        "failed": len(rows) - len(done),
        "reported_ok": sum(1 for r in done if r["ok"]),
        "cache_hits": sum(1 for r in done if r["cache_hit"]),
        "measured_paid_calls": len(paid),
        "model_calls_total": sum(r["model_calls"] for r in done),
    }
    if paid:
        elapsed = [r["elapsed_ms"] for r in paid]
        wall = [r["wall_ms"] for r in paid]
        summary["elapsed_ms"] = {
            "mean": int(statistics.mean(elapsed)),
            "median": int(statistics.median(elapsed)),
            "p95": percentile(elapsed, 95),
            "min": min(elapsed), "max": max(elapsed),
        }
        summary["wall_ms_mean"] = int(statistics.mean(wall))
        summary["tokens"] = {
            "prompt_total": sum(r["tokens"]["prompt"] for r in paid),
            "completion_total": sum(r["tokens"]["completion"] for r in paid),
            "total": sum(r["tokens"]["total"] for r in paid),
            "total_per_image": round(
                sum(r["tokens"]["total"] for r in paid) / float(len(paid)), 1),
        }
        if args.price_in is not None and args.price_out is not None:
            cost = (summary["tokens"]["prompt_total"] / 1e6 * args.price_in
                    + summary["tokens"]["completion_total"] / 1e6 * args.price_out)
            summary["cost_cny"] = {
                "total": round(cost, 6),
                "per_image": round(cost / len(paid), 6),
                "price_in_per_million": args.price_in,
                "price_out_per_million": args.price_out,
            }
        else:
            summary["cost_cny"] = None
    if graded:
        summary["accuracy"] = {
            "graded": len(graded),
            "type_correct": sum(1 for r in graded if r["type_correct"]),
            "type_accuracy": round(
                sum(1 for r in graded if r["type_correct"]) / float(len(graded)), 4),
        }
    else:
        summary["accuracy"] = None

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump({"summary": summary, "results": rows}, handle,
                  ensure_ascii=False, indent=2, sort_keys=True)

    print()
    print("recognised %d/%d, reported_ok %d, cache_hits %d, model calls %d"
          % (summary["images_recognised"], summary["images_requested"],
             summary["reported_ok"], summary["cache_hits"],
             summary["model_calls_total"]))
    if summary["cache_hits"]:
        print("note: %d cache hits excluded from latency/token/cost averages"
              % summary["cache_hits"])
    if done and not paid:
        print("nothing measured: every image was served from cache, so there is")
        print("no real latency or cost data here. Drop --keep-cache or clear %s"
              % cache_dir)
    if "elapsed_ms" in summary:
        e = summary["elapsed_ms"]
        print("latency ms over %d paid calls: mean %d median %d p95 %d min %d max %d"
              % (len(paid), e["mean"], e["median"], e["p95"], e["min"], e["max"]))
        t = summary["tokens"]
        print("tokens: prompt %d completion %d total %d (%.1f per paid image)"
              % (t["prompt_total"], t["completion_total"], t["total"],
                 t["total_per_image"]))
        if summary["cost_cny"]:
            c = summary["cost_cny"]
            print("cost: CNY %.6f total, %.6f per paid image"
                  % (c["total"], c["per_image"]))
        else:
            print("cost: not computed - pass --price-in/--price-out in CNY per million tokens")
    if summary["accuracy"]:
        a = summary["accuracy"]
        print("accuracy: %d/%d types correct (%.1f%%)"
              % (a["type_correct"], a["graded"], a["type_accuracy"] * 100))
    else:
        print("accuracy: not graded - pass --labels with expected types, or read the field dump in the report")
    print("report: %s" % os.path.abspath(args.out))

    if not args.keep_cache:
        shutil.rmtree(cache_dir, ignore_errors=True)
    return 0 if summary["images_recognised"] else 1


if __name__ == "__main__":
    sys.exit(main())
