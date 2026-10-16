#!/usr/bin/env python3
"""Every console control can be reached without a mouse, and has a name.

    python3 scripts/check_console_controls.py

## What went wrong

`check_control_labels.py` has covered the Flutter app since the day controls
there were found with empty accessible names. The HQ console had no equivalent,
and ten of its controls were clickable `<div>`s — no `role`, no `tabIndex`, no
key handler. A pointer could use them; a keyboard, a screen reader and voice
control could not. Among them:

  * the **agency desk's incident card**. Expanding it is the only way to the
    escalation log, the evidence, the live feed and both action buttons — on the
    one surface an outside agency ever sees, since they have no console, no feed
    and no audit screen;
  * the **responder picker** a dispatcher assigns an emergency with. Worse than
    unreachable: it had a real `<input type="checkbox">` inside whose `onChange`
    was `() => {}`, with a comment saying "Handled by div onClick". So the
    checkbox was focusable, looked operable, and did nothing. A dispatcher
    working by keyboard could tab onto it, press Space, see nothing change, and
    conclude the roster was broken;
  * the **evidence thumbnails** on both the dossier and the agency desk, which
    called `window.open` from a div — unreachable by keyboard, with no address
    to copy, and the one shape a popup blocker treats as suspicious;
  * the **counts that filter the board** (`StatBar`), and the SMS-fallback chip.

And the console had no `keydown` handler anywhere, so the incident dossier — a
fixed overlay over the feed and the map, which an operator opens on the wrong
report often — could only be dismissed with a pointer.

## What this checks

1. **An element with `onClick` is operable.** It must be natively interactive
   (`button`, `a`, `input`, `select`, `textarea`, `label`, `summary`) or carry
   both a `role` and a `tabIndex`, so that focus and activation exist.

2. **A control that is not a control says so, in the markup.** A backdrop and a
   `stopPropagation` wrapper have a click handler and are not controls. Rather
   than a list of exempt line numbers in this file — which rots the moment
   anything moves — each declares `data-pointer-only="<reason>"` where the
   reason is visible to the next person reading the JSX. The attribute must
   carry a non-empty reason.

3. **Every button has a name.** `aria-label`, `title`, or text in its own
   children (a string literal counts: a label that is a ternary of two phrases
   is still a name). An icon is not a name — `<RefreshCw />` alone read as
   "button" and nothing else.

## What it deliberately does not check

Focus management. The dossier is now `role="dialog" aria-modal="true"` and
closes on Escape, but focus is neither moved into it nor trapped, which a modal
dialog is supposed to do. Doing it properly means turning a 500-line inline
block into a component; it is recorded in E2E_AUDIT_REPORT.md as open rather
than half-done here, and a gate that claimed to check it would be the worse
lie.

Nor does it check the Flutter app — `check_control_labels.py` owns that, and
the two codebases express the same requirement in different vocabularies.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONSOLE = REPO / 'hq-dashboard-next' / 'src'

NATIVE = {'button', 'a', 'input', 'select', 'textarea', 'label', 'summary', 'details'}

# Comments blanked rather than removed, so line numbers survive. This check's
# own prose quotes the markup it looks for, and so do the files it reads: the
# JSX comments next to each converted control describe the defect.
BLOCK = re.compile(r'/\*.*?\*/', re.S)
LINE = re.compile(r'//[^\n]*')


def blank(text: str) -> str:
    out = BLOCK.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)
    return LINE.sub(lambda m: ' ' * len(m.group(0)), out)


def files() -> list[Path]:
    return [
        p for p in sorted(CONSOLE.rglob('*.tsx'))
        if '.test.' not in p.name
    ]


def opening_tags(text: str):
    """Every JSX opening tag, as (tag, attrs, line, index after the tag).

    Scanned rather than matched with a regex, because an attribute's value can
    contain the character that ends a tag:

        <button onClick={() => {}}>

    `[^>]*?` stops at the `>` of the arrow. The first version of this check did
    exactly that, so for EVERY button with an inline handler — which is most of
    them — it read `{}}><X /></button>` as the button's children, found the
    stray `>`, and concluded the button had a name. The rule passed on an
    icon-only button with no label, which is the one thing it exists to catch,
    and it was mutation-testing that said so.
    """
    i = 0
    n = len(text)
    while i < n:
        if text[i] != '<':
            i += 1
            continue
        m = re.match(r'<([A-Za-z][\w.]*)', text[i:])
        if not m:
            i += 1
            continue
        tag = m.group(1)
        j = i + m.end()
        depth = 0           # brace depth inside an attribute value
        quote = ''          # ' " or ` while inside a string
        while j < n:
            ch = text[j]
            if quote:
                if ch == quote:
                    quote = ''
            elif ch in '\'"`':
                quote = ch
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            elif ch == '>' and depth == 0:
                break
            j += 1
        attrs = text[i + m.end():j]
        yield tag, attrs, text[:i].count('\n') + 1, j + 1
        i = j + 1


failures: list[str] = []
checked = 0
declared_exemptions = 0

for path in files():
    text = blank(path.read_text())
    rel = path.relative_to(REPO)

    # ---- 1 & 2. a clickable thing must be operable, or declare itself ------
    for tag, attrs, line, _after in opening_tags(text):
        if 'onClick' not in attrs:
            continue
        checked += 1
        if tag in NATIVE:
            continue
        if tag[0].isupper():
            continue  # A component; its own definition is checked on its own.
        exemption = re.search(r'data-pointer-only\s*=\s*"([^"]*)"', attrs)
        if exemption:
            if not exemption.group(1).strip():
                failures.append(
                    f'{rel}:{line} — <{tag}> is declared `data-pointer-only` with no '
                    'reason. The reason is the point: it is what tells the next '
                    'person reading this JSX why a click handler here is not a '
                    'control anybody has to be able to reach.')
            else:
                declared_exemptions += 1
            continue
        has_role = 'role=' in attrs
        has_tabindex = 'tabIndex' in attrs
        if has_role and has_tabindex:
            continue
        missing = []
        if not has_role:
            missing.append('a role')
        if not has_tabindex:
            missing.append('a tabIndex')
        failures.append(
            f'{rel}:{line} — <{tag}> has an onClick and {" and ".join(missing)}. '
            'A pointer can use it and a keyboard, a screen reader and voice '
            'control cannot. Make it a <button> (or an <a> if it navigates), or '
            'give it a role, a tabIndex and a key handler — or, if it is a '
            'backdrop rather than a control, say so with '
            'data-pointer-only="<reason>".')

    # ---- 3. a button has a name ------------------------------------------
    for tag, attrs, line, after in opening_tags(text):
        if tag != 'button':
            continue
        if attrs.rstrip().endswith('/'):
            continue  # Self-closing: no children to read.
        close = text.find('</button>', after)
        body = text[after:close] if close != -1 else ''
        if 'aria-label' in attrs or 'title=' in attrs:
            continue
        # Child ELEMENTS are dropped; a quoted string or bare text is a name.
        # A ternary of two phrases — `{busy ? 'SAVING…' : 'SAVE'}` — is a name,
        # which is why the literals inside expressions are kept.
        without_elements = re.sub(r'<[^>]*>', '', body)
        if re.search(r"""['"`][^'"`]{2,}['"`]""", without_elements):
            continue
        if re.sub(r'[\s{}?:()]', '', without_elements):
            continue
        failures.append(
            f'{rel}:{line} — a <button> with no accessible name. It reads as '
            '"button" and nothing else to a screen reader. An icon is not a '
            'name: add an aria-label (and a title, so a pointer gets the same '
            'words).')

if failures:
    print('A console control cannot be reached, or cannot be named:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_console_controls.py for why this matters.')
    sys.exit(1)

print('Every console control is operable and named:')
print(f'  * {checked} click handlers across {len(files())} files')
print(f'  * {declared_exemptions} declared pointer-only, each with its reason in the markup')
print('  * every <button> has a name from a label, a title or its own text')
