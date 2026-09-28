#!/usr/bin/env python3
"""Fail if an icon-only control carries no label.

WHY THIS EXISTS
---------------
Fifteen of this app's nineteen `IconButton`s had no `tooltip`. Four of them sat
in the agent dashboard's app bar — the menu, the map/list toggle, the command
broadcast and SIGN OUT — on the primary screen a responder works from.

An icon with no tooltip has no accessible name. Three consequences, in order of
how much they matter:

1. A responder using TalkBack or VoiceOver is offered four unlabelled buttons
   on the screen they run an emergency from. One of them signs them out.
2. A new officer has to press a control to find out what it does. On this
   screen, one of the things it might do is broadcast to the whole state.
3. Automated testing cannot see them either. The interaction sweep reported a
   single control named `(icon)` for the entire agent dashboard, and the
   per-tier buttons — which are the ones that differ between UNIT, WARD, LGA
   and HQ — went unexercised for exactly this reason. That is how a missing
   label turns into missing coverage, quietly.

`tooltip:` is the right fix rather than a bare `Semantics` wrapper: Flutter maps
it to the accessible name AND shows it on long-press, so the sighted user who
does not recognise the icon is helped by the same line of code.

    python3 scripts/check_control_labels.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

# Widgets that render as a control with no text of their own, so whatever
# identifies them has to be supplied.
ICON_ONLY = ("IconButton(", "FloatingActionButton(")

# A generated file is not hand-written and has no controls in it.
GENERATED = (".g.dart", ".freezed.dart")


def body_of(text: str, start: int) -> tuple[str, int]:
    """The argument list of a call opening at `start`, and the index after it."""
    i = start
    depth = 1
    while i < len(text) and depth:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
        i += 1
    return text[start : i - 1], i


def unlabelled() -> list[tuple[str, int, str]]:
    """(file, line, widget) for every icon-only control with no name."""
    found = []
    for path in sorted(LIB.rglob("*.dart")):
        if path.name.endswith(GENERATED):
            continue
        text = path.read_text()
        for widget in ICON_ONLY:
            for m in re.finditer(re.escape(widget), text):
                body, _ = body_of(text, m.end())
                # `tooltip:` is the usual answer; an explicit Semantics label or
                # a `semanticLabel` on the icon is just as good an answer.
                if any(k in body for k in ("tooltip:", "semanticLabel:", "Semantics(")):
                    continue
                found.append(
                    (
                        str(path.relative_to(ROOT)),
                        text.count("\n", 0, m.start()) + 1,
                        widget.rstrip("("),
                    )
                )
    return found


def main() -> int:
    bad = unlabelled()
    if bad:
        print("Icon-only controls with no accessible name:")
        for path, line, widget in bad:
            print(f"  {path}:{line}  {widget}")
        print()
        print("Add `tooltip: '...'`. Flutter uses it as the accessible name and")
        print("shows it on long-press, so it serves the screen-reader user and")
        print("the sighted user who does not recognise the icon at once.")
        return 1

    total = 0
    for path in LIB.rglob("*.dart"):
        if path.name.endswith(GENERATED):
            continue
        text = path.read_text()
        total += sum(text.count(w) for w in ICON_ONLY)
    print(f"OK: all {total} icon-only controls carry an accessible name.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
