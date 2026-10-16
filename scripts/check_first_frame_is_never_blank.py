#!/usr/bin/env python3
"""Start-up must always put something legible on the screen.

    python3 scripts/check_first_frame_is_never_blank.py

## What went wrong

An installed release APK opened to a featureless pale page and stopped there.
Not a crash: the process stayed up, nothing moved, and no message was shown.

Four facts, each from source rather than from guesswork, compose into that:

  1. `main()` wrapped `await SupabaseConfig.init()` in a try/catch that logged
     the failure and carried on to `runApp`.
  2. `AuthNotifier`'s constructor calls `initAuth()`, which reached
     `SupabaseConfig.client` SYNCHRONOUSLY. That constructor runs inside the
     `appRouter` provider, which `RainbowApp.build` watches — so it runs
     during the app's very first `build()`.
  3. `Supabase.instance` guards itself with an `assert`
     (supabase_flutter/lib/src/supabase.dart:43-49), and `client` is a `late`
     field (line 173). A release build strips the assert, so the getter threw
     `LateInitializationError` instead of the explanatory assertion a debug
     build shows.
  4. A throw during `build()` hands the frame to `ErrorWidget.builder`, whose
     default composes its message inside `assert(() { ... }())`
     (flutter/lib/src/widgets/framework.dart:5680-5692). In release that
     message is `''`, so `RenderErrorBox` builds no paragraph at all
     (rendering/error.dart:37-60) and paints only its background:
     `const Color(0xF0C0C0C0)`, pale grey (error.dart:112-117, 156).

So the app's own start-up failure wore no message. In debug, every one of
those four steps is loud; in release, all four are silent. The repository had
a passing "app boots without throwing" test the whole time — it overrides
`AuthNotifier` with one whose `initAuth()` does nothing, which is precisely
the line that died, and its own comment says so.

A second, independent path to the same blank page: `main()` ran its platform
set-up as bare statements inside `runZonedGuarded` with `runApp` last. A throw
from any of them — a plugin that failed to register, a platform channel that
rejected a call — jumped to the zone handler, which logged it. `runApp` was
then never called, no Flutter frame was ever produced, and the window kept
showing the launch background.

## What this checks

  1. `main.dart` installs a readable `ErrorWidget.builder` before `runApp`, so
     no build-time throw anywhere in the app can present as a blank page.
  2. Everything `main.dart` awaits before `runApp` is guarded, so no step can
     stop the first frame from being drawn.
  3. When start-up cannot complete, `main.dart` runs a failure screen rather
     than returning with no root widget at all.
  4. `SupabaseConfig.client` refuses with a message that survives a release
     build, instead of an assert and a `late` field.
  5. `lib/` reaches the client only through that getter — `Supabase.instance`
     anywhere else reintroduces the stripped assert.
  6. `AuthNotifier.initAuth` cannot throw out of a build.
  7. The failure screen shows the error it was given, needs no `Theme`,
     `Directionality` or `MediaQuery`, and takes its words from the
     translation table rather than from an assert.

## What it does not check

That the APK runs. It cannot: there is no Android SDK, no device and no
emulator in this container. This encodes the rules, and `test/first_frame_
test.dart` exercises the behaviour.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'

MAIN = LIB / 'main.dart'
STARTUP = LIB / 'core' / 'startup' / 'startup_failure.dart'
SUPABASE = LIB / 'core' / 'supabase' / 'supabase_config.dart'
AUTH = LIB / 'providers' / 'auth_provider.dart'

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def live(path: Path) -> str:
    """The file's code, with comments blanked.

    This check's own documentation quotes the defect it exists to prevent —
    `Supabase.instance.client`, an unguarded `await` — and a check that reads
    its own warning as a violation fails on the fix.
    """
    src = path.read_text()
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), src,
                 flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith('//') else line
        for line in src.split('\n')
    )


def blank_strings(src: str) -> str:
    """The code with string literals replaced by spaces, lengths preserved.

    Only used for brace and paren matching: a `{` inside a message would
    otherwise be counted as an opening block.
    """
    out = list(src)
    i = 0
    while i < len(src):
        ch = src[i]
        if ch in "'\"":
            quote = ch
            triple = src[i:i + 3] == quote * 3
            end = i + (3 if triple else 1)
            while end < len(src):
                if src[end] == '\\':
                    end += 2
                    continue
                if triple and src[end:end + 3] == quote * 3:
                    end += 3
                    break
                if not triple and src[end] == quote:
                    end += 1
                    break
                if not triple and src[end] == '\n':
                    break
                end += 1
            for j in range(i + 1, min(end, len(src))):
                if out[j] != '\n':
                    out[j] = ' '
            i = end
            continue
        i += 1
    return ''.join(out)


def spans(src: str, opener: str, open_ch: str, close_ch: str) -> list[tuple[int, int]]:
    """Every (start, end) region in `src` covered by a balanced `opener`."""
    flat = blank_strings(src)
    found: list[tuple[int, int]] = []
    for match in re.finditer(re.escape(opener), flat):
        start = flat.find(open_ch, match.start())
        if start < 0:
            continue
        depth = 0
        for index in range(start, len(flat)):
            if flat[index] == open_ch:
                depth += 1
            elif flat[index] == close_ch:
                depth -= 1
                if depth == 0:
                    found.append((match.start(), index))
                    break
    return found


for path in (MAIN, STARTUP, SUPABASE, AUTH):
    if not path.is_file():
        sys.exit(f'{path.relative_to(REPO)} is missing — this check cannot '
                 'say anything about a start-up path that is not there.')

main_src = live(MAIN)
startup_src = live(STARTUP)
supabase_src = live(SUPABASE)
auth_src = live(AUTH)

# ── 1. A build-time throw must never be silent ────────────────────────────────
install = main_src.find('installReadableErrorWidget()')
first_run_app = main_src.find('runApp(')
if install < 0:
    fail('lib/main.dart never calls `installReadableErrorWidget()`. Without '
         'it, an exception from any `build()` in the app renders Flutter\'s '
         'stock error widget, which in a RELEASE build paints '
         '`Color(0xF0C0C0C0)` and no text — the blank page an installed APK '
         'opened to.')
elif 0 <= first_run_app < install:
    fail('lib/main.dart calls `runApp` before `installReadableErrorWidget()`. '
         'A throw during the first build would then still paint a blank pale '
         'box; the installer has to come first.')

if 'ErrorWidget.builder' not in startup_src:
    fail(f'{STARTUP.relative_to(REPO)} no longer sets `ErrorWidget.builder`, '
         'so nothing replaces the stock release error widget.')

# ── 2. Nothing may stop the first frame ───────────────────────────────────────
if first_run_app < 0:
    fail('lib/main.dart never calls `runApp`.')
else:
    before_frame = main_src[:first_run_app]
    # An `await` before the first frame is guarded if it sits inside a
    # `runStartupStep(...)` call or inside a `try { ... }` block. Both are
    # matched by balancing brackets rather than by counting keywords, so a
    # nested await inside a guarded closure is recognised as guarded.
    guards = (spans(before_frame, 'runStartupStep(', '(', ')')
              + spans(before_frame, 'runRequiredStartupStep(', '(', ')')
              + spans(before_frame, 'try {', '{', '}'))
    unguarded: list[str] = []
    for match in re.finditer(r'^\s*(?:await|final\s+\w+\s*=\s*await)\s+(.+)$',
                             before_frame, re.M):
        statement = match.group(1).strip()
        if statement.startswith(
                ('runStartupStep(', 'runRequiredStartupStep(', 'boot()')):
            continue
        if any(start <= match.start() <= end for start, end in guards):
            continue
        line = before_frame[:match.start()].count('\n') + 1
        unguarded.append(f'  * lib/main.dart:{line} — `{statement[:60]}`')
    if unguarded:
        fail('lib/main.dart awaits something unguarded before `runApp`:\n'
             + '\n'.join(unguarded)
             + '\nA throw there goes to the zone handler and `runApp` is never'
               ' reached, so no Flutter frame is ever produced and the window'
               ' keeps showing the launch background. Wrap it in'
               ' `runStartupStep(...)` or a try/catch, or move it after the'
               ' first frame.')

# The one step the app cannot be built without gets a bound, not just a
# catch. The first version of main.dart wrapped `SupabaseConfig.init()` in a
# try/catch, on the argument that it does no network I/O and so cannot hang.
# That argument is not a bound, and a step that never finishes before `runApp`
# produces exactly the blank page this check exists to prevent.
required = re.search(
    r'runRequiredStartupStep\(.*?\n\s*\)', main_src, re.S)
if not required:
    fail('lib/main.dart no longer runs its required start-up step through '
         '`runRequiredStartupStep`, which is the only thing bounding it. A '
         'try/catch around `SupabaseConfig.init()` catches a throw and not a '
         'stall, and a stall before `runApp` is the same blank page.')
elif 'limit:' not in required.group():
    fail('lib/main.dart calls `runRequiredStartupStep` with no `limit:`, so '
         'the one step the first frame waits on is unbounded again.')

if 'runRequiredStartupStep' not in startup_src:
    fail(f'{STARTUP.relative_to(REPO)} no longer defines '
         '`runRequiredStartupStep`.')
elif '.timeout(' not in startup_src:
    fail(f'{STARTUP.relative_to(REPO)}: `runRequiredStartupStep` no longer '
         'applies its `limit` with `.timeout(`, so it bounds nothing.')

if 'runStartupStep' not in startup_src:
    fail(f'{STARTUP.relative_to(REPO)} no longer defines `runStartupStep`, '
         'which is the only thing standing between a failing start-up step '
         'and a window with nothing in it.')

# ── 3. A start-up that cannot finish must still show a screen ─────────────────
if 'StartupFailureScreen' not in main_src:
    fail('lib/main.dart never runs `StartupFailureScreen`. When start-up '
         'cannot complete — no Supabase client, so every screen would throw '
         'reaching for one — it has to say so. Returning without a root '
         'widget leaves the launch background on screen for ever.')
if not re.search(r'if\s*\(\s*!\s*SupabaseConfig\.isInitialized\s*\)',
                 main_src):
    fail('lib/main.dart no longer checks `SupabaseConfig.isInitialized` '
         'before building the app. Catching the init failure and carrying on '
         'to `runApp` is what put the throw inside the first build.')

# ── 4. The client getter must speak in release too ────────────────────────────
if 'isInitialized' not in supabase_src:
    fail(f'{SUPABASE.relative_to(REPO)} no longer exposes `isInitialized`, so '
         'start-up cannot tell whether it has a client before it builds a UI '
         'that needs one.')
getter = re.search(r'static SupabaseClient get client.*?\n(?=\s*\}?\s*$|\})',
                   supabase_src, re.S)
getter_src = getter.group() if getter else ''
if 'StateError' not in getter_src:
    fail(f'{SUPABASE.relative_to(REPO)}: `client` no longer throws a '
         '`StateError` naming the problem. `Supabase.instance` guards itself '
         'with an `assert`, which release strips, and `client` is a `late` '
         'field — so the release failure was `LateInitializationError` from '
         'whichever widget asked first, with no hint that start-up was what '
         'had failed.')

# ── 5. One path to the client ─────────────────────────────────────────────────
for path in sorted(LIB.rglob('*.dart')):
    if path == SUPABASE:
        continue
    code = live(path)
    for match in re.finditer(r'\bSupabase\.instance\b', code):
        line = code[:match.start()].count('\n') + 1
        fail(f'{path.relative_to(REPO)}:{line} reaches `Supabase.instance` '
             'directly. That getter is guarded only by an assert, which a '
             'release build strips, and the field behind it is `late` — use '
             '`SupabaseConfig.client`, which refuses with a message instead.')

# ── 6. The first build must not be able to throw ──────────────────────────────
init_auth = re.search(r'void initAuth\(\).*?\n  \}', auth_src, re.S)
if not init_auth:
    fail(f'{AUTH.relative_to(REPO)}: `initAuth()` not found — this check '
         'cannot confirm the app\'s first build is safe.')
else:
    body = init_auth.group()
    if 'SupabaseConfig.client' in body:
        guarded = re.search(
            r'try\s*\{[^}]*SupabaseConfig\.client[^}]*\}\s*(?:on\s+\w+\s+)?'
            r'catch',
            body, re.S)
        if not guarded:
            fail(f'{AUTH.relative_to(REPO)}: `initAuth()` reaches '
                 '`SupabaseConfig.client` without catching. This runs inside '
                 'the `AuthNotifier` constructor, which runs inside the '
                 '`appRouter` provider, which `RainbowApp.build` watches — so '
                 'a throw here IS a throw during the app\'s first build, and '
                 'in release that is a pale rectangle with no text on it.')
    reports = re.search(r'resolutionError:\s*(?!null\b)\S', body)
    if not reports:
        fail(f'{AUTH.relative_to(REPO)}: `initAuth()` no longer reports a '
             'missing client as a non-null `resolutionError`. The router '
             'reads that and sends the user to the login screen '
             '(`computeRedirect`, the role-unresolved branch); without it a '
             'failure is either a throw or a silent hold on the splash '
             'screen, which is the blank page again with extra steps.')
    if not re.search(r'isLoading:\s*false', body):
        fail(f'{AUTH.relative_to(REPO)}: `initAuth()` no longer clears '
             '`isLoading` when it cannot reach the client. `computeRedirect` '
             'returns null while auth is loading, so the app would sit on the '
             'splash screen for ever.')

# ── 7. The failure screen has to be able to draw ──────────────────────────────
for forbidden, why in (
    ('Theme.of(', 'there is no `Theme` above `MaterialApp`, and this screen '
                  'can be asked to replace `MaterialApp` itself'),
    ('MediaQuery.of(', 'there is no `MediaQuery` either'),
    ('Scaffold(', '`Scaffold` needs a `Material` ancestor this screen cannot '
                  'assume'),
    ('GoogleFonts.', 'a font lookup is one more thing that can fail on the '
                     'screen whose job is to report a failure'),
):
    if forbidden in startup_src:
        fail(f'{STARTUP.relative_to(REPO)} uses `{forbidden}` — {why}.')

if not re.search(r"Text\(\s*'\$error'", startup_src):
    fail(f'{STARTUP.relative_to(REPO)} no longer RENDERS the error it was '
         'given — logging it is not the same thing, and a log is exactly '
         'what nobody holding the phone can read. A screen that says only '
         '"something went wrong" leaves the user with nothing to report and '
         'us with nothing to go on.')

if 'errorBuilder' not in startup_src:
    fail(f'{STARTUP.relative_to(REPO)} loads an image with no `errorBuilder`. '
         'A missing asset would throw from the failure screen, Flutter would '
         'ask `ErrorWidget.builder` for a replacement, and get this screen '
         'again.')

for key in ('startup_failed_title', 'startup_failed_body',
            'startup_failed_retry'):
    if f"'{key}'" not in startup_src:
        fail(f'{STARTUP.relative_to(REPO)} no longer reads `{key}`. The only '
             'strings in the app that must render with no locale loaded are '
             'these; hard-coding them is how one of them ends up English-only.')

# The title is shown in all three languages, because a person who reads only
# Hausa gets nothing from a blank page either. Each language has to come from
# the table, so a hard-coded line cannot quietly replace one of them.
title_reads = re.findall(
    r"Translations\.get\(\s*\n?\s*'startup_failed_title',\s*\n?\s*"
    r'AppLanguage\.(\w+)', startup_src)
for language in ('english', 'hausa', 'pidgin'):
    if language not in title_reads:
        fail(f'{STARTUP.relative_to(REPO)} no longer reads '
             f'`startup_failed_title` for {language}. The failure screen '
             'shows the headline in all three languages on purpose: it is the '
             'one screen that renders before any locale has been loaded, so '
             'it cannot ask which language the user chose.')

if failures:
    print('The first frame can be blank again:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

print('OK: start-up always ends in a frame that says something.')
print('  * lib/main.dart installs a readable error widget before runApp')
print('  * nothing it awaits before the first frame can stop that frame')
print('  * the one required step is bounded, not merely caught')
print('  * a start-up that cannot finish renders a screen that explains it')
print('  * SupabaseConfig.client refuses with a message release keeps')
print('  * lib/ reaches the client only through that getter')
print('  * AuthNotifier.initAuth cannot throw out of the first build')
print('  * the failure screen needs no Theme, Directionality or MediaQuery')
