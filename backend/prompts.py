"""Stage-1 classifier prompt and stage-2 per-type extraction prompts."""

from passes import SPEC, PASS_TYPES, TYPE_LABELS

CLASSIFY_SYSTEM = (
    "你是截图分类器。只输出一个类型标识符，不要输出任何解释、标点或换行。"
)

CLASSIFY_USER = (
    "这张截图属于以下哪一类？只输出标识符本身。\n\n"
    + "\n".join("%s = %s" % (k, TYPE_LABELS[k]) for k in PASS_TYPES)
    + "\nunknown = 以上都不是，或截图里没有可识别的凭证\n"
)


def _field_lines(pass_type):
    spec = SPEC[pass_type]
    lines = ["必填字段："]
    for key in spec["required"]:
        lines.append("  - %s" % key)
    optional = spec.get("optional", [])
    if optional:
        lines.append("可选字段（截图里没有就省略该键，不要填 null 或空字符串）：")
        for key in optional:
            lines.append("  - %s" % key)
    return "\n".join(lines)


def extract_system(pass_type):
    return (
        "你是凭证信息提取器。从截图里读出%s的关键信息，"
        "严格输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。"
        "读不到的字段直接省略。时间统一用 ISO 8601（如 2026-11-28T14:30:00）。"
        % TYPE_LABELS[pass_type]
    )


def extract_user(pass_type):
    spec = SPEC[pass_type]
    parts = [
        "提取这张%s截图的信息。" % spec["label"],
        "",
        _field_lines(pass_type),
        "",
        "所有类型都可以带这些通用可选字段：",
        "  - brand（商家/品牌名）",
        "  - location（地点全称）",
        "  - qr_payload（如果截图里有二维码且你能读出内容）",
        "  - notes（其它值得显示在卡片上的信息）",
    ]
    enums = spec.get("enums")
    if enums:
        parts.append("")
        parts.append("枚举字段的取值范围：")
        for key, allowed in enums.items():
            parts.append("  - %s: %s" % (key, " | ".join(allowed)))
    return "\n".join(parts)


FALLBACK_SYSTEM = (
    "你是凭证信息提取器。先判断这张截图属于哪一类凭证，再提取关键信息。"
    "严格输出一个 JSON 对象，不要 markdown 代码块，不要任何解释文字。"
)

FALLBACK_USER = (
    "输出格式：\n"
    '{\n  "type": "<类型标识符>",\n  "fields": { ... }\n}\n\n'
    "可选的 type：\n"
    + "\n".join("%s = %s" % (k, TYPE_LABELS[k]) for k in PASS_TYPES)
    + "\n\nfields 里放该类型的关键信息，字段名用英文小写下划线，"
    "例如 train_no / depart_at / seat / code / title / plate_no / service。"
    "读不到的字段直接省略。时间用 ISO 8601。"
)


def repair_user(pass_type, errors):
    return (
        "你上次输出的 JSON 有以下问题：\n"
        + "\n".join("- %s" % e for e in errors)
        + "\n\n请重新输出修正后的完整 JSON 对象，只要 JSON，不要解释。"
    )
