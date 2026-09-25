#!/usr/bin/env python3
"""Regenerate the HQ dashboard's tactical map from the app's canonical one.

The app writes alerts.geo_lga / geo_ward / geo_pu from
lib/core/constants/tactical_mapping.dart. The dashboard filters incidents by
those same values, so if the two files carry different jurisdiction names the
filters silently match nothing.

Both files did list all 17 LGAs — but not one of the 17 matched. The app writes
upper case ('JOS NORTH'), the dashboard held title case ('Jos North'), so every
comparison failed on case alone. On top of that the app spelled one LGA
'BARIKIN LADI' for the statutory BARKIN LADI, two ids disagreed
(LGA_BARIKIN_LADI vs LGA_BARKIN_LADI, LGA_QUA_AN_PAN vs LGA_QUAN_PAN), and the
dashboard's ward data was a fraction of the app's: 142 wards and 378 polling
units against 207 and 4,987.

The Dart file is the source of truth because it is what reaches the database.
This script projects it into hq-dashboard-next/src/lib/tactical_mapping.ts,
replacing only the `plateauTacticalMap` array and leaving the rest of that file
(interfaces, STATE_SECURITY_AGENCIES, helpers) untouched.

    ./scripts/sync-tactical-map.py            # rewrite the TypeScript
    ./scripts/sync-tactical-map.py --check    # exit 1 if it is out of date
"""
from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART = REPO / "lib/core/constants/tactical_mapping.dart"
TS = REPO / "hq-dashboard-next/src/lib/tactical_mapping.ts"

TS_ANCHOR = "export const plateauTacticalMap: TacticalJurisdiction[] = "

# A Dart string literal in either quote style, no escapes used in this data.
STR = r"""(?:'([^']*)'|"([^"]*)")"""


def _s(m: re.Match, i: int) -> str:
    """Pick whichever quote style matched."""
    return m.group(i) if m.group(i) is not None else m.group(i + 1)


def _balanced(text: str, start: int, open_ch: str, close_ch: str) -> tuple[str, int]:
    """Return the substring inside the brackets beginning at `start`."""
    assert text[start] == open_ch, text[start : start + 40]
    depth = 0
    i = start
    in_str: str | None = None
    while i < len(text):
        c = text[i]
        if in_str:
            if c == in_str:
                in_str = None
        elif c in "'\"":
            in_str = c
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return text[start + 1 : i], i + 1
        i += 1
    raise ValueError("unbalanced brackets")


def parse_dart() -> list[dict]:
    src = io.open(DART, encoding="utf-8").read()

    anchor = "const List<TacticalJurisdiction> plateauTacticalMap = "
    at = src.index(anchor) + len(anchor)
    body, _ = _balanced(src, src.index("[", at), "[", "]")

    jurisdictions: list[dict] = []
    for jm in re.finditer(r"TacticalJurisdiction\(", body):
        seg, _ = _balanced(body, body.index("(", jm.start()), "(", ")")

        jid = re.search(r"id:\s*" + STR, seg)
        jname = re.search(r"name:\s*" + STR, seg)
        if not jid or not jname:
            continue

        wards: list[dict] = []
        wat = seg.find("wards:")
        if wat != -1:
            wbody, _ = _balanced(seg, seg.index("[", wat), "[", "]")
            for wm in re.finditer(r"TacticalWard\(", wbody):
                wseg, _ = _balanced(wbody, wbody.index("(", wm.start()), "(", ")")
                wid = re.search(r"id:\s*" + STR, wseg)
                wname = re.search(r"name:\s*" + STR, wseg)
                if not wid or not wname:
                    continue
                pus: list[str] = []
                pat = wseg.find("pollingUnits:")
                if pat != -1:
                    pbody, _ = _balanced(wseg, wseg.index("[", pat), "[", "]")
                    pus = [_s(m, 1) for m in re.finditer(STR, pbody)]
                wards.append(
                    {"id": _s(wid, 1), "name": _s(wname, 1), "pollingUnits": pus}
                )

        jurisdictions.append(
            {"id": _s(jid, 1), "name": _s(jname, 1), "wards": wards}
        )

    return jurisdictions


def render_banner(summary: str) -> str:
    """The file's whole leading comment, title line included.

    The hand-written title claimed "142 Official Wards, 378 Verified Local
    Security Posts" while the array below it held 207 and 4,987 — a comment
    asserting counts that nothing checked. These come from the data.
    """
    return (
        f"// Plateau State tactical mapping — {summary}.\n"
        "//\n"
        "// GENERATED — do not edit by hand.\n"
        "//\n"
        "// Projected from lib/core/constants/tactical_mapping.dart by\n"
        "// scripts/sync-tactical-map.py. That Dart file is the source of truth\n"
        "// because it is what the app writes into alerts.geo_lga / geo_ward /\n"
        "// geo_pu; these values are what the dashboard's filters compare against,\n"
        "// so the two must use the same words or the filters match nothing.\n"
        "//\n"
        "// Run ./scripts/sync-tactical-map.py after changing the Dart map.\n"
        "\n"
    )


def main() -> int:
    check = "--check" in sys.argv
    data = parse_dart()

    lgas = len(data)
    wards = sum(len(j["wards"]) for j in data)
    pus = sum(len(w["pollingUnits"]) for j in data for w in j["wards"])
    summary = f"{lgas} LGAs, {wards} wards, {pus} polling units"

    src = io.open(TS, encoding="utf-8").read()
    at = src.index(TS_ANCHOR)
    # Past the END of the anchor: the anchor text itself contains the `[]` of
    # `TacticalJurisdiction[]`, and matching that pair leaves the whole old array
    # in the tail, which then gets emitted a second time.
    arr_start = src.index("[", at + len(TS_ANCHOR))
    _, after = _balanced(src, arr_start, "[", "]")
    # Swallow the trailing semicolon and newline of the old declaration.
    tail = src[after:].lstrip(";")

    # Everything between the two generated comment blocks — the interfaces and
    # STATE_SECURITY_AGENCIES — is hand-maintained and passes through untouched.
    head = src[:at]
    head_lines = head.split("\n")
    # Drop the generated leading comment block...
    while head_lines and (head_lines[0].startswith("//") or not head_lines[0].strip()):
        head_lines.pop(0)
    # ...and the generated banner sitting directly above the anchor.
    while head_lines and (head_lines[-1].startswith("//") or not head_lines[-1].strip()):
        head_lines.pop()
    middle = "\n".join(head_lines).strip()

    rendered = (
        render_banner(summary)
        + (middle + "\n\n" if middle else "")
        + TS_ANCHOR
        + json.dumps(data, indent=2, ensure_ascii=False)
        + ";\n"
        + tail.lstrip("\n")
    )

    if check:
        if rendered != src:
            print(f"tactical map OUT OF DATE — Dart has {summary}", file=sys.stderr)
            print("run ./scripts/sync-tactical-map.py", file=sys.stderr)
            return 1
        print(f"tactical map in sync ({summary})")
        return 0

    if rendered == src:
        print(f"tactical map already in sync ({summary})")
        return 0

    io.open(TS, "w", encoding="utf-8").write(rendered)
    print(f"wrote {TS.relative_to(REPO)} — {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
