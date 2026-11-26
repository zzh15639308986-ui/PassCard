"""Pass type catalogue and field validation."""

from datetime import datetime

DATETIME_FIELDS = {
    "occurred_at", "expires_at", "pickup_by", "depart_at", "arrive_at",
    "start_at", "end_at", "ride_at", "boarding_time", "next_charge_at",
    "charged_at", "trial_ends_at",
}

NUMBER_FIELDS = {"price", "duration_min"}

COMMON_OPTIONAL = ["location", "notes", "qr_payload", "brand"]

SPEC = {
    "pickup_food": {
        "label": "取餐码",
        "required": ["code"],
        "optional": ["store", "pickup_by", "order_no"],
    },
    "pickup_parcel": {
        "label": "快递取件码",
        "required": ["code"],
        "optional": ["carrier", "station", "expires_at", "recipient_phone_tail"],
    },
    "train": {
        "label": "火车票",
        "required": ["train_no", "depart_at"],
        "optional": ["from_station", "to_station", "arrive_at", "carriage",
                     "seat", "seat_class", "passenger", "gate"],
    },
    "flight": {
        "label": "机票",
        "required": ["flight_no", "depart_at"],
        "optional": ["from_airport", "to_airport", "arrive_at", "seat", "gate",
                     "boarding_time", "passenger", "pnr", "terminal_from",
                     "terminal_to"],
    },
    "movie": {
        "label": "电影票",
        "required": ["title", "start_at"],
        "optional": ["cinema", "screen", "seat", "duration_min", "language",
                     "version"],
    },
    "show": {
        "label": "演出门票",
        "required": ["title", "start_at"],
        "optional": ["venue", "seat", "price"],
    },
    "ride": {
        "label": "打车订单",
        "required": ["plate_no"],
        "optional": ["platform", "vehicle", "vehicle_color", "pickup_point",
                     "destination", "ride_at", "driver_phone_tail"],
    },
    "voucher": {
        "label": "优惠券/兑换码",
        "required": ["code"],
        "optional": ["merchant", "expires_at", "terms", "value"],
    },
    "subscription": {
        "label": "订阅与账单",
        "required": ["service"],
        "optional": ["price", "currency", "cycle", "next_charge_at",
                     "charged_at", "trial_ends_at", "status"],
        "enums": {"cycle": ["monthly", "quarterly", "yearly", "weekly",
                            "one_time", "unknown"],
                  "status": ["active", "cancelled", "trial", "expired"]},
    },
}

PASS_TYPES = tuple(SPEC)
TYPE_LABELS = {k: v["label"] for k, v in SPEC.items()}

_CN_DATETIME_FORMATS = (
    "%Y年%m月%d日 %H:%M",
    "%Y年%m月%d日%H:%M",
    "%Y年%m月%d日",
    "%Y/%m/%d %H:%M",
    "%Y/%m/%d",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%m月%d日 %H:%M",
    "%H:%M",
)


def parse_datetime(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value)
    if not isinstance(value, str):
        raise ValueError("not a string")
    text = value.strip()
    if not text:
        raise ValueError("empty")
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        pass
    for fmt in _CN_DATETIME_FORMATS:
        try:
            parsed = datetime.strptime(text, fmt)
            if fmt == "%H:%M":
                today = datetime.now()
                parsed = parsed.replace(year=today.year, month=today.month,
                                        day=today.day)
            return parsed
        except ValueError:
            continue
    raise ValueError("unrecognised datetime: %r" % text)


def normalise_fields(pass_type, fields):
    """Coerce datetimes to ISO 8601 and numbers to float. Returns (fields, warnings)."""
    spec = SPEC[pass_type]
    allowed = set(spec["required"]) | set(spec.get("optional", [])) | set(COMMON_OPTIONAL)
    out = {}
    warnings = []

    for key, value in fields.items():
        if key not in allowed:
            warnings.append("dropped unknown field %r" % key)
            continue
        if value is None or (isinstance(value, str) and not value.strip()):
            continue
        if key in DATETIME_FIELDS:
            try:
                out[key] = parse_datetime(value).isoformat()
            except ValueError as exc:
                warnings.append("%s: %s" % (key, exc))
                out[key] = value
        elif key in NUMBER_FIELDS:
            try:
                out[key] = float(str(value).replace(",", "").replace("¥", "")
                                 .replace("￥", "").strip())
            except ValueError:
                warnings.append("%s: not a number (%r)" % (key, value))
                out[key] = value
        else:
            out[key] = value.strip() if isinstance(value, str) else value
    return out, warnings


def validate(pass_type, fields):
    """Returns a list of human-readable errors. Empty list means valid."""
    if pass_type not in SPEC:
        return ["unknown pass type %r" % pass_type]

    spec = SPEC[pass_type]
    errors = []

    for key in spec["required"]:
        value = fields.get(key)
        if value is None or (isinstance(value, str) and not value.strip()):
            errors.append("missing required field %r" % key)

    for key, allowed in spec.get("enums", {}).items():
        value = fields.get(key)
        if value is not None and str(value).lower() not in allowed:
            errors.append("%s=%r not in %s" % (key, value, "/".join(allowed)))

    for key in DATETIME_FIELDS:
        value = fields.get(key)
        if value is None:
            continue
        try:
            parse_datetime(value)
        except ValueError as exc:
            errors.append("%s: %s" % (key, exc))

    for key in NUMBER_FIELDS:
        value = fields.get(key)
        if value is None:
            continue
        try:
            float(str(value).replace(",", "").replace("¥", "").strip())
        except ValueError:
            errors.append("%s: not a number (%r)" % (key, value))

    return errors
