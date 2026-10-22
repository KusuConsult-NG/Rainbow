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

    # ── A NAME IS NOT ENOUGH IF THE BUTTON CANNOT BE PRESSED ────────────────
    #
    # `Semantics(button: true, excludeSemantics: true, child: <tappable>)`
    # announces a button and offers no way to activate it: `excludeSemantics`
    # drops the child's semantics, and the child's tap action goes with them.
    # A screen-reader user hears "Allow location, button" and cannot press it.
    #
    # Found by the control sweep, which pressed seven report chips through the
    # accessibility tree and reported that nothing happened. It was right.
    # `lib/shared/widgets/rainbow_app_bar.dart` already carried a comment
    # explaining this from the previous time, and the comment did not stop it
    # being written again two screens away — which is what a check is for.
    #
    # `button: true` is the trigger, so a Semantics that labels a non-control
    # (the map in live_tracking_screen.dart wraps FlutterMap with
    # `container: true` to hide the tile layers' noise) is not caught by it.
    unpressable = []
    for path in sorted(LIB.rglob("*.dart")):
        if path.name.endswith(GENERATED):
            continue
        text = path.read_text()
        for match in re.finditer(r"Semantics\(", text):
            depth, end = 0, len(text)
            for index in range(match.end() - 1, len(text)):
                if text[index] == "(":
                    depth += 1
                elif text[index] == ")":
                    depth -= 1
                    if depth == 0:
                        end = index
                        break
            block = text[match.start():end]
            head = block[:block.find("child:")] if "child:" in block else block
            if "excludeSemantics: true" not in head:
                continue
            if re.search(r"on(Tap|LongPress|Increase|Decrease):", head):
                continue
            # The trigger is what it WRAPS, not what it calls itself.
            #
            # `button: true` was the first version's trigger and it had a hole:
            # dropping that one line made the check blind while the control
            # stayed just as unpressable. The thing that matters is that a tap
            # widget is being hidden.
            #
            # Named directly so that `Semantics(container: true, label: …,
            # excludeSemantics: true, child: FlutterMap(…))` in
            # live_tracking_screen.dart is not caught: it hides a map's tile
            # layers, which is what excludeSemantics is for, and the onTap
            # buried in its markers is not a control this is labelling.
            child = block[block.find("child:") + len("child:"):].lstrip()
            if not re.match(
                r"(GestureDetector|InkWell|TextButton|ElevatedButton|"
                r"OutlinedButton|IconButton|FilledButton)\(", child):
                continue
            if not re.search(r"on(Tap|Pressed):", block):
                continue
            line = text[:match.start()].count("\n") + 1
            unpressable.append((path.relative_to(ROOT), line))

    if unpressable:
        print("Buttons a screen reader can name but never press:")
        for path, line in unpressable:
            print(f"  {path}:{line}")
        print()
        print("`excludeSemantics: true` drops the child's semantics, and the")
        print("child's tap action with them. Put `onTap:` on the Semantics")
        print("itself as well as on the detector underneath it.")
        return 1

    total = 0
    for path in LIB.rglob("*.dart"):
        if path.name.endswith(GENERATED):
            continue
        text = path.read_text()
        total += sum(text.count(w) for w in ICON_ONLY)
    print(f"OK: all {total} icon-only controls carry an accessible name,")
    print("    and every Semantics button that hides its child can be pressed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
