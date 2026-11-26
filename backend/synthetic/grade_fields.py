"""Field-level grading of measure.py reports against a truth file.

Stricter than measure.py's own type check: compares every expected field with
NFKC and full-width normalisation plus a numeric tolerance, and counts
hallucinated qr payloads and silently dropped fields.

    py grade_fields.py [--truth truth.json] report-a.json report-b.json ...

--truth must come first and defaults to truth.json beside this script. The
real-screenshot truth file is not in version control (it holds a passenger
name, a phone tail and an order number), so a fresh clone can only grade the
synthetic fixtures.
"""

import json
import os
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))


def norm(value):
    text = unicodedata.normalize("NFKC", str(value))
    for full, half in (("（", "("), ("）", ")"), ("：", ":"), ("，", ","),
                       ("　", " "), ("·", ""), (" ", "")):
        text = text.replace(full, half)
    return text.strip().lower()


def field_equal(expected, actual):
    if norm(expected) == norm(actual):
        return True
    try:
        return abs(float(expected) - float(actual)) < 1e-6
    except (TypeError, ValueError):
        return False


def main():
    args = sys.argv[1:]
    truth_path = os.path.join(HERE, "truth.json")
    if args and args[0] == "--truth":
        truth_path = args[1]
        args = args[2:]
    truth = json.load(open(truth_path, encoding="utf-8"))
    by_file = {item["file"]: item for item in truth["items"]}

    for path in args:
        report = json.load(open(path, encoding="utf-8"))
        model = os.environ.get("ARK_MODEL", os.path.basename(path))
        rows = report["results"]
        print()
        print("==== %s ====" % os.path.basename(path))

        type_ok = 0
        field_total = 0
        field_ok = 0
        missing = []
        wrong = []
        hallucinated_qr = 0
        dropped = []
        infra_failed = 0

        for row in rows:
            item = by_file.get(row["file"])
            if item is None:
                continue
            # A row that never reached the model (HTTP 404, missing file) says
            # nothing about recognition quality; counting it as a miss would
            # let an infrastructure outage masquerade as a bad model.
            if row.get("error") or row.get("type") is None:
                infra_failed += 1
                continue
            if row.get("type") == item["expected_type"]:
                type_ok += 1
            else:
                print("  TYPE MISS %-24s want=%-14s got=%s"
                      % (row["file"], item["expected_type"], row.get("type")))
            got = row.get("fields") or {}
            for key, want in item["expected_fields"].items():
                field_total += 1
                if key in got and field_equal(want, got[key]):
                    field_ok += 1
                elif key not in got:
                    missing.append("%s.%s" % (row["file"], key))
                else:
                    wrong.append("%s.%s want=%r got=%r"
                                 % (row["file"], key, want, got[key]))
            if "qr_payload" in got and "qr_payload" not in item["expected_fields"]:
                hallucinated_qr += 1
            for warning in row.get("warnings") or []:
                if "dropped unknown field" in warning:
                    dropped.append("%s: %s" % (row["file"], warning))

        graded = len([r for r in rows if r["file"] in by_file
                      and not r.get("error") and r.get("type") is not None])
        print("  reached the model:  %d/%d (%d failed before recognition)"
              % (graded, len([r for r in rows if r["file"] in by_file]), infra_failed))
        print("  type accuracy:      %d/%d = %.0f%%"
              % (type_ok, graded, 100.0 * type_ok / max(graded, 1)))
        print("  field accuracy:     %d/%d = %.0f%%"
              % (field_ok, field_total, 100.0 * field_ok / max(field_total, 1)))
        print("  fields missing:     %d  %s" % (len(missing), "; ".join(missing[:8])))
        print("  fields wrong:       %d" % len(wrong))
        for line in wrong[:10]:
            print("      %s" % line)
        print("  hallucinated qr:    %d (barcodes carry no payload)" % hallucinated_qr)
        print("  dropped unknown:    %d  %s" % (len(dropped), "; ".join(dropped[:5])))

        summary = report["summary"]
        print("  latency ms:         %s" % json.dumps(summary.get("elapsed_ms")))
        print("  tokens per image:   %s" % summary.get("tokens", {}).get("total_per_image"))
        print("  cost per image CNY: %s"
              % (summary.get("cost_cny") or {}).get("per_image"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
