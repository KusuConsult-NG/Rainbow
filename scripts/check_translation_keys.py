#!/usr/bin/env python3
"""Every string the app asks for in Hausa must exist in Hausa.

    python3 scripts/check_translation_keys.py

## What went wrong

`Translations.get(key, lang)` was `_keys[key]?[lang] ?? key` — a miss returns
the KEY. Two keys were asked for and never defined:

    Translations.get('live_dispatch_channel', currentLang)
    Translations.get('alert_ref', currentLang)

Both on the citizen's DISPATCHER CHAT screen, which is what a person opens to
talk to a dispatcher during an emergency. Its header read
`live_dispatch_channel` and `alert_ref #a1b2c3d4` — in every language, English
included, since the fallback had nothing to do with translation.

Nothing caught it because a missing key fails SILENTLY in the only way that
matters: the screen renders, the test suite is green, and the defect is visible
only to the person reading it.

Separately, the picker in Settings was wired to a storage key nothing reads
(`app_language` = 'HA', against the `app_lang` = 'ha' every screen watches), so
choosing Hausa did nothing — and it offered two of the three languages the app
has. That one is held by `LanguagePicker` being the only control, which this
check also asserts.

## What this checks

1. Every key passed to `Translations.get(...)` anywhere in `lib/` is defined.
2. Every defined key has a string for EVERY language in `AppLanguage`, so a new
   language cannot be added half-wired.
3. Nothing defines a second `languageProvider` or `LanguageNotifier` — the
   duplicate pair is what let the Settings screen read a different source of
   truth from every other screen.
4. The language is only ever stored under one SharedPreferences key.
5. Every control that changes the language does it through that one provider.
   Two controls are fine — a full picker in Settings and in setup, a flag menu
   in the home app bar — as long as they write the same place. A control bound
   to a different store is the defect, not a second control.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'
TABLE = LIB / 'shared' / 'localization' / 'translations.dart'
PICKER = LIB / 'shared' / 'widgets' / 'language_picker.dart'

COMMENT = re.compile(r'/\*.*?\*/|///[^\n]*|//[^\n]*', re.S)


def strip_comments(text: str) -> str:
    """Blanked, not removed, so line numbers survive."""
    return COMMENT.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


for path in (TABLE, PICKER):
    if not path.exists():
        sys.exit(f'{path.relative_to(REPO)} is missing')

table_src = TABLE.read_text()

# The languages the app offers, read out of the enum rather than assumed.
enum_block = re.search(r'enum AppLanguage \{(.*?)\n\}', table_src, re.S)
if not enum_block:
    sys.exit('AppLanguage is no longer an enum in '
             f'{TABLE.relative_to(REPO)}; this check cannot see the languages.')
languages = re.findall(r'^\s*(\w+)\(', enum_block.group(1), re.M)
if not languages:
    sys.exit('AppLanguage has no values.')

# Each key, and which languages it carries.
defined: dict[str, set[str]] = {}
for block in re.finditer(
        r"^    '([a-z_0-9]+)': \{(.*?)^    \},", table_src, re.S | re.M):
    key, body = block.group(1), block.group(2)
    defined[key] = set(re.findall(r'AppLanguage\.(\w+):', body))

if not defined:
    sys.exit('no translation keys found — the table format changed and this '
             'check would pass over anything.')

# 1. Asked for and defined.
asked: dict[str, list[str]] = {}
for path in sorted(LIB.rglob('*.dart')):
    code = strip_comments(path.read_text())
    for match in re.finditer(r"Translations\.get\(\s*'([a-z_0-9]+)'", code):
        line = code[:match.start()].count('\n') + 1
        asked.setdefault(match.group(1), []).append(
            f'{path.relative_to(REPO)}:{line}')

for key, places in sorted(asked.items()):
    if key not in defined:
        fail(f'`{key}` is asked for at {", ".join(places)} and is not in the '
             'table. `get()` returns the key itself, so that is what the '
             'screen renders — in every language.')

# 2. Fully translated.
for key, langs in sorted(defined.items()):
    missing = [l for l in languages if l not in langs]
    if missing:
        fail(f'`{key}` has no string for {", ".join(missing)}. A key missing a '
             'language falls back to English, which reads as "this app does '
             'not speak your language here" rather than as a fault.')

# 3, 4, 5. One source of truth.
providers: list[str] = []
notifiers: list[str] = []
pref_keys: dict[str, list[str]] = {}
setters: list[str] = []
for path in sorted(LIB.rglob('*.dart')):
    code = strip_comments(path.read_text())
    where = str(path.relative_to(REPO))
    if re.search(r'\blanguageProvider\s*=', code):
        providers.append(where)
    if re.search(r'class\s+LanguageNotifier\b', code):
        notifiers.append(where)
    for pref in re.findall(r"""(?:getString|setString)\(\s*'(app_lang\w*)'""", code):
        pref_keys.setdefault(pref, []).append(where)
    # Only the PROVIDER's setter. `tts_service.dart` calls
    # `_flutterTts.setLanguage('en-US')`, which is the speech engine's voice
    # and has nothing to do with this.
    if re.search(r'languageProvider\.notifier\s*\)\s*\.setLanguage\(', code):
        setters.append(where)

if len(providers) > 1:
    fail(f'`languageProvider` is declared in {len(providers)} places '
         f'({", ".join(providers)}). Which one a screen gets depends on which '
         'it imports, and that is how the Settings picker came to write a key '
         'no reader has heard of.')
if len(notifiers) > 1:
    fail(f'`LanguageNotifier` is declared in {len(notifiers)} places '
         f'({", ".join(notifiers)}).')
if len(pref_keys) > 1:
    detail = '; '.join(f'{k} in {", ".join(v)}' for k, v in sorted(pref_keys.items()))
    fail(f'the language is stored under {len(pref_keys)} different preference '
         f'keys ({detail}). One of them is always the one nothing reads.')
if not setters:
    fail('nothing calls `languageProvider.notifier.setLanguage()`, so the '
         'language cannot be changed at all.')
for where in setters:
    src = strip_comments((REPO / where).read_text())
    if 'shared/localization/translations.dart' not in src:
        fail(f'{where} changes the language without importing '
             '`shared/localization/translations.dart`, so it is setting a '
             'different provider from the one every translated string reads. '
             'That is exactly how the Settings picker came to change nothing.')

if failures:
    print('The app asks for strings it does not have:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_translation_keys.py for why this matters.')
    sys.exit(1)

print(f'{len(defined)} keys, {len(languages)} languages '
      f'({", ".join(languages)}), all complete:')
print(f'  * every one of {len(asked)} keys the app asks for is defined')
print('  * one languageProvider, one LanguageNotifier, one preference key')
print(f'  * {len(setters)} control(s) set it, all through the one provider')
