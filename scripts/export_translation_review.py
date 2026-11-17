#!/usr/bin/env python3
"""Write the draft translations out as a sheet a Hausa or Pidgin speaker can correct.

    python3 scripts/export_translation_review.py review.csv

Reads the block in lib/shared/localization/translations.dart between

    // ---- DRAFT TRANSLATIONS, AWAITING A NATIVE SPEAKER
    // ---- END OF DRAFT TRANSLATIONS AWAITING A NATIVE SPEAKER

and writes one row per key: the screen it is on, the English, the draft Hausa
and Pidgin, and two empty columns for the speaker's corrections. A spreadsheet
opens the CSV directly (UTF-8, so ɓ ɗ ƙ ƴ survive).

Once a key has been checked, put the corrected text in the table and move the
key above the first marker. The sheet then no longer lists it.
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TABLE = REPO / 'lib' / 'shared' / 'localization' / 'translations.dart'
BEGIN = '// ---- DRAFT TRANSLATIONS, AWAITING A NATIVE SPEAKER'
END = '// ---- END OF DRAFT TRANSLATIONS AWAITING A NATIVE SPEAKER'

ENTRY = re.compile(r"^    '([a-z0-9_]+)': \{\n((?:      AppLanguage\.\w+:[^\n]*\n)+)    \},", re.M)
LINE = re.compile(r"AppLanguage\.(\w+): '((?:[^'\\]|\\.)*)',")
SCREEN = re.compile(r'^    // (?!-)(.+)$', re.M)


def unescape(text: str) -> str:
    return re.sub(r'\\(.)', r'\1', text)


def drafts(source: str) -> list[dict[str, str]]:
    start = source.index(BEGIN)
    end = source.index(END)
    block = source[start:end]
    rows = []
    for match in ENTRY.finditer(block):
        # The screen is the last one-line comment above the entry.
        screens = SCREEN.findall(block[:match.start()])
        values = {lang: unescape(text) for lang, text in LINE.findall(match.group(2))}
        rows.append({
            'key': match.group(1),
            'screen': screens[-1] if screens else '',
            'english': values.get('english', ''),
            'hausa_draft': values.get('hausa', ''),
            'hausa_correction': '',
            'pidgin_draft': values.get('pidgin', ''),
            'pidgin_correction': '',
        })
    return rows


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rows = drafts(TABLE.read_text(encoding='utf-8'))
    # A screen marked REVIEW FIRST (the emergency PIN) leads the sheet.
    rows.sort(key=lambda r: 'REVIEW FIRST' not in r['screen'])
    if not rows:
        sys.exit('no draft translations found between the markers')
    out = Path(sys.argv[1])
    with out.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f'{len(rows)} draft translations written to {out}')


if __name__ == '__main__':
    main()
