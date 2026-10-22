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



# A control nobody wrote as a control.
#
# `IconButton` and `FloatingActionButton` were the two widgets the first version
# of this file knew about, because they were the two it found. A tap target
# hand-rolled out of `GestureDetector` + `Icon` is the same thing to a screen
# reader and was outside its scope entirely — which is how the interaction sweep
# came to report one control named `(icon)` on the safe-zone screen.
HAND_ROLLED = ("GestureDetector(", "InkWell(", "InkResponse(")


def blank_strings(text: str) -> str:
    """Blank out string literals AND comments, keeping every byte offset.

    The ancestor walk below balances parentheses, so a paren inside a string or
    a comment — `// tap (here)` — makes it walk into the wrong widget. Offsets
    have to survive exactly, because the line numbers this prints come from
    them.

    Comments are not an afterthought here. The first version skipped only
    strings, and `// This screen's own state` on line 277 of
    `emergency_active_screen.dart` opened a literal that never closed — so the
    rest of that file was blanked and all four of its tap targets vanished from
    the check, SUBMIT on the emergency PIN pad among them. A detector that
    silently stops seeing is worse than no detector, and this one hid three
    real findings for as long as it existed. That is the argument for running a
    check against known faults instead of reading it.

    Handles, in order: triple-quoted strings, line comments, block comments,
    then ordinary quoted strings with backslash escapes. A raw string
    (`r'...'`) needs no special case — blanking its contents is right anyway.
    """
    out = list(text)
    i, n = 0, len(text)

    def blank(start: int, upto: int) -> None:
        for k in range(start, min(upto, n)):
            if out[k] != "\n":
                out[k] = " "

    TRIPLES = ("'''", '"""')
    while i < n:
        three = text[i:i + 3]
        if three in TRIPLES:
            close = text.find(three, i + 3)
            stop = n if close == -1 else close + 3
            blank(i, stop)
            i = stop
            continue
        two = text[i:i + 2]
        if two == "//":
            nl = text.find("\n", i)
            stop = n if nl == -1 else nl
            blank(i, stop)
            i = stop
            continue
        if two == "/*":
            close = text.find("*/", i + 2)
            stop = n if close == -1 else close + 2
            blank(i, stop)
            i = stop
            continue
        c = text[i]
        if c == "'" or c == '"':
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            stop = min(j + 1, n)
            blank(i, stop)
            i = stop
            continue
        i += 1
    return "".join(out)


def own_args(body: str) -> str:
    """Only the characters at depth 0 of an argument list.

    `"excludeSemantics: true" in body` is wrong and quietly so: a Semantics
    that wraps a whole widget contains every nested node's arguments too.
    `voice_note_player.dart` labels its player at the top and its play button
    further down, and the button's own correct `excludeSemantics` made the
    OUTER container look like it excluded everything — so the check reported
    the one widget in this codebase that gets this right. Twice now, in two
    different ways, from reading a body as if it were flat.
    """
    out, depth = [], 0
    for ch in body:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def ancestors(text: str, pos: int, levels: int = 5) -> list[tuple[str, int]]:
    """The calls enclosing `pos`, nearest first, as (identifier, paren index).

    Walks backwards balancing parentheses rather than reading a fixed window of
    lines above. A window got this wrong: `voice_note_player.dart` wraps its
    play button in a correctly labelled `Semantics` seven non-empty lines above
    the `InkWell`, and a six-line window reported the one control in this
    codebase that does it right.
    """
    found: list[tuple[str, int]] = []
    i, depth = pos - 1, 0
    while i >= 0 and len(found) < levels:
        c = text[i]
        if c == ")":
            depth += 1
        elif c == "(":
            if depth == 0:
                j = i - 1
                while j >= 0 and (text[j].isalnum() or text[j] in "_$."):
                    j -= 1
                name = text[j + 1 : i]
                if name:
                    found.append((name, i))
            else:
                depth -= 1
        i -= 1
    return found


def unnamed_tap_targets() -> list[tuple[str, int, str]]:
    """(file, line, widget) for every hand-rolled icon-only control with no name."""
    found = []
    for path in sorted(LIB.rglob("*.dart")):
        if path.name.endswith(GENERATED):
            continue
        raw = path.read_text()
        text = blank_strings(raw)
        for widget in HAND_ROLLED:
            for m in re.finditer(re.escape(widget), text):
                body, _ = body_of(text, m.end())
                if not re.search(r"on(Tap|LongPress)\s*:", body):
                    continue
                # Icon-only: an icon in the subtree and no text of its own.
                if not re.search(r"\bIcon\s*\(", body):
                    continue
                if re.search(r"\bText\s*\(", body):
                    continue
                # Named from the inside.
                if re.search(r"tooltip\s*:|semanticLabel\s*:|Semantics\s*\(", body):
                    continue
                # Or named by a wrapper — but only one whose `child:` IS this
                # control.
                #
                # A nearest-ancestor search alone was too generous:
                # `Semantics(label: 'Keypad', child: Row(children: [...]))`
                # would have cleared every unnamed button in that row at once,
                # which is the opposite of what a label on a group means to a
                # screen reader. The wrapper has to be this control's direct
                # parent, which is checkable exactly: whatever follows `child:`
                # must be the control itself.
                named = False
                for name, paren in ancestors(text, m.start()):
                    if name not in ("Semantics", "Tooltip"):
                        continue
                    outer, _ = body_of(text, paren + 1)
                    if not re.search(r"\b(label|message)\s*:", outer):
                        continue
                    # The wrapper's OWN `child:`, at depth 0 of its argument
                    # list. A plain `find` hits a nested one first: the
                    # attachment thumbnail's `onTap:` builds a `Dialog(child:
                    # …)` inline, so the first `child:` in the body belongs to
                    # that dialog and the real one is forty lines later. The
                    # check then reported the control as unnamed when it had
                    # just been named, which is the sort of false positive that
                    # gets a gate deleted.
                    key, d = -1, 0
                    for idx, ch in enumerate(outer):
                        if ch in "([{":
                            d += 1
                        elif ch in ")]}":
                            d -= 1
                        elif d == 0 and outer.startswith("child:", idx):
                            key = idx
                            break
                    if key == -1:
                        continue
                    child_at = paren + 1 + key + len("child:")
                    while child_at < len(text) and text[child_at] in " \n\t":
                        child_at += 1
                    if child_at == m.start():
                        named = True
                        break
                if named:
                    continue
                found.append(
                    (
                        str(path.relative_to(ROOT)),
                        raw.count("\n", 0, m.start()) + 1,
                        widget.rstrip("("),
                    )
                )
    return found


# A LABEL INSIDE AN EXCLUDED SUBTREE IS NOT A LABEL.
#
# `excludeSemantics: true` drops the semantics of the WHOLE child subtree, not
# just one node. So a correctly labelled control nested anywhere under one is
# invisible to a screen reader, and a check that only asks "does it have a
# label" passes over it — which is the exact shape of defect this audit keeps
# finding, written into the check meant to catch it.
#
# `live_tracking_screen.dart` is the real case. flutter_map registers a
# pan-and-zoom recognizer, so without the exclusion the whole map surface
# reaches the tree as one unlabelled button covering the screen — a defect the
# sweep already found once. With the exclusion, every responder marker inside
# it goes too. The two requirements genuinely conflict, and resolving it means
# giving that screen a responder LIST instead of relying on map pins.
#
# So this does not pretend the control is fine, and it does not fail a build
# over a decision that needs a feature. It demands the acknowledgement be
# WRITTEN AT THE CONTROL, as a comment carrying this token, and it prints every
# one it finds. A new unreachable control cannot appear quietly; somebody has
# to type the token.
ACKNOWLEDGED = "SEMANTICS-UNREACHABLE:"


def unreachable_tap_targets() -> tuple[list[tuple[str, int, str]], list[tuple[str, int]]]:
    """Tap targets buried under an `excludeSemantics: true` ancestor.

    Returns (unacknowledged, acknowledged). The first fails the build.
    """
    bad: list[tuple[str, int, str]] = []
    known: list[tuple[str, int]] = []
    for path in sorted(LIB.rglob("*.dart")):
        if path.name.endswith(GENERATED):
            continue
        raw = path.read_text()
        text = blank_strings(raw)
        for widget in HAND_ROLLED:
            for m in re.finditer(re.escape(widget), text):
                body, _ = body_of(text, m.end())
                if not re.search(r"on(Tap|LongPress)\s*:", body):
                    continue
                # Which ancestor excludes this control's subtree? The control's
                # OWN Semantics parent does not count: excluding its child is
                # how a labelled wrapper is supposed to work.
                excluded_by = None
                anc = ancestors(text, m.start(), levels=8)
                # Where this control's comment could be: above the control, or
                # above the labelled wrapper the control sits inside. The
                # wrapper's arguments stand between the two, so a walk from the
                # control alone stops at `button: true` and never reaches the
                # paragraph explaining why it is there.
                anchors = [line_of := raw.count("\n", 0, m.start()) + 1]
                if anc:
                    anchors.append(raw.count("\n", 0, anc[0][1]) + 1)
                for depth, (name, paren) in enumerate(anc):
                    if name != "Semantics":
                        continue
                    outer, _ = body_of(text, paren + 1)
                    if "excludeSemantics: true" not in own_args(outer):
                        continue
                    if depth == 0:
                        continue  # its own labelled wrapper
                    excluded_by = raw.count("\n", 0, paren) + 1
                    break
                if excluded_by is None:
                    continue
                line = raw.count("\n", 0, m.start()) + 1
                # The acknowledgement has to be AT the control, in the
                # comment block directly above it.
                #
                # NOT a fixed number of lines above it. A twenty-line window
                # was the first version and it broke the moment the comment it
                # was looking for grew to twenty-one lines — so rewrapping a
                # paragraph turned this check red with nothing wrong. Walk the
                # contiguous comment block instead, however long it is. (Third
                # time a fixed window has been wrong in this file's history;
                # the other two are documented above.)
                src_lines = raw.split("\n")
                block = []
                for anchor in anchors:
                    back = anchor - 2
                    while back >= 0:
                        stripped = src_lines[back].strip()
                        if stripped.startswith(("//", "///")) or not stripped:
                            block.append(src_lines[back])
                            back -= 1
                            continue
                        break
                if ACKNOWLEDGED in "\n".join(block):
                    known.append((str(path.relative_to(ROOT)), line))
                else:
                    bad.append((str(path.relative_to(ROOT)), line, f"excluded by the Semantics at line {excluded_by}"))
    return bad, known


# A MAP IS NOT A BUTTON, ON EVERY SCREEN THAT HAS ONE.
#
# flutter_map registers a tap recognizer for panning and zooming, so an
# unwrapped `FlutterMap` reaches the accessibility tree as an unlabelled button
# covering the screen — announced as "button", doing nothing when activated.
#
# This was diagnosed once, fixed on `live_tracking_screen.dart`, written up in
# a comment there, and applied to none of the other three maps in the app. The
# control sweep went on failing on the shelter screen for exactly this, every
# run, reporting one control named `(icon)` that did nothing. Nobody had asked
# which OTHER screens have a map. T-78.
#
# So: every FlutterMap carries a label and excludes its own subtree, or this
# fails. `RainbowMap` takes the label as a required parameter with no default,
# which closes the same hole for its three call sites.
#
# WHAT THIS CANNOT SEE. It is lexical. A marker list built in its own statement
# — `final markers = <Marker>[…]` — and handed to `MarkerLayer(markers:
# markers)` is inside the excluded subtree at RUN time and nowhere near it in
# the SOURCE, so the unreachable-control check above cannot connect the two.
# safe_zone_screen.dart is exactly that shape. Its shelters are offered as a
# list of real buttons beside the map for that reason, and the reason is
# written at the markers. A check that cannot see something should say so
# rather than be trusted to.
def maps_that_are_buttons() -> list[tuple[str, int]]:
    """(file, line) for every FlutterMap that is not a labelled, excluded map."""
    bad = []
    for path in sorted(LIB.rglob("*.dart")):
        if path.name.endswith(GENERATED):
            continue
        raw = path.read_text()
        text = blank_strings(raw)
        for m in re.finditer(r"\bFlutterMap\s*\(", text):
            line = raw.count("\n", 0, m.start()) + 1
            named = False
            for name, paren in ancestors(text, m.start(), levels=3):
                if name != "Semantics":
                    continue
                outer, _ = body_of(text, paren + 1)
                args = own_args(outer)
                if not re.search(r"\blabel\s*:", args):
                    continue
                if "excludeSemantics: true" not in args:
                    continue
                # Its DIRECT child, at depth 0 of its own argument list.
                key, d = -1, 0
                for idx, ch in enumerate(outer):
                    if ch in "([{":
                        d += 1
                    elif ch in ")]}":
                        d -= 1
                    elif d == 0 and outer.startswith("child:", idx):
                        key = idx
                        break
                if key == -1:
                    continue
                at = paren + 1 + key + len("child:")
                while at < len(text) and text[at] in " \n\t":
                    at += 1
                if at == m.start():
                    named = True
                    break
            if not named:
                bad.append((str(path.relative_to(ROOT)), line))
    return bad


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

    # ── AND A CONTROL NOBODY WROTE AS A CONTROL ─────────────────────────────
    #
    # The two widgets above are the two this file was written from. A tap
    # target made by hand out of `GestureDetector` and an `Icon` has exactly
    # the same problem and was never in scope, so the shelter marker — the
    # control that picks which shelter a frightened person is routed to — had
    # no accessible name, and neither did SUBMIT on the emergency PIN pad.
    homemade = unnamed_tap_targets()
    if homemade:
        print("Hand-rolled icon-only controls with no accessible name:")
        for path, line, widget in homemade:
            print(f"  {path}:{line}  {widget}")
        print()
        print("A GestureDetector around an Icon is a button to everyone except")
        print("a screen reader and the interaction sweep, which sees it as")
        print("`(icon)` and cannot report what it does. Wrap it in")
        print("`Semantics(button: true, label: '...', onTap: <same handler>)`")
        print("— and keep the onTap on the Semantics, or see the check below.")
        return 1

    # ── A MAP IS NOT A BUTTON, ON EVERY SCREEN THAT HAS ONE ─────────────────
    maps = maps_that_are_buttons()
    if maps:
        print("Maps that reach the accessibility tree as unlabelled buttons:")
        for path, line in maps:
            print(f"  {path}:{line}")
        print()
        print("flutter_map's pan-and-zoom recognizer makes an unwrapped map a")
        print("button covering the screen: announced as \"button\", doing")
        print("nothing when pressed. Wrap it in `Semantics(container: true,")
        print("label: <what the map shows>, excludeSemantics: true, child:")
        print("FlutterMap(...))`, and offer anything tappable inside it — a")
        print("marker — somewhere outside the exclusion as well.")
        return 1

    # ── AND A NAME UNDER AN EXCLUDED SUBTREE IS NOT A NAME ──────────────────
    buried, acknowledged = unreachable_tap_targets()
    if buried:
        print("Tap targets a screen reader cannot reach at all:")
        for path, line, why in buried:
            print(f"  {path}:{line}  {why}")
        print()
        print("`excludeSemantics: true` drops the whole child subtree, so a")
        print("label on something nested under one has no effect. Either stop")
        print("excluding, or — if the exclusion is there for a reason that")
        print("cannot be undone — write the reason at the control in a comment")
        print(f"carrying `{ACKNOWLEDGED}`, so the next person reads it")
        print("instead of finding it.")
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
    homemade_total = 0
    for path in LIB.rglob("*.dart"):
        if path.name.endswith(GENERATED):
            continue
        text = path.read_text()
        total += sum(text.count(w) for w in ICON_ONLY)
        homemade_total += sum(text.count(w) for w in HAND_ROLLED)
    print(f"OK: all {total} icon-only controls carry an accessible name,")
    print(f"    all {homemade_total} hand-rolled tap targets that show only an")
    print("    icon carry one too, and every Semantics button that hides its")
    print("    child can be pressed.")
    # Never silent. A pass that hides a known gap is the defect this whole
    # audit is about.
    if acknowledged:
        print()
        print(f"    {len(acknowledged)} control(s) carry a correct label a screen reader")
        print("    still cannot reach, each with its reason written at the control:")
        for path, line in acknowledged:
            print(f"      {path}:{line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
