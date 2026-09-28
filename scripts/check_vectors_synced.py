#!/usr/bin/env python3
"""Assert the console's copy of the wire-format vectors matches the Dart one.

WHY THIS GATE EXISTS
--------------------
Two independent implementations of each offline wire format — Dart on the
handset, TypeScript at HQ — are checked against vectors produced by the DART
encoder, so neither is graded on its own reading of the prose. That arrangement
is what caught nothing so far, which is the point: it is cheap and it makes a
whole class of silent disagreement impossible.

But it only works if the copy the TypeScript tests import is the copy the Dart
generator wrote. They are two files in two directories, copied by hand, and a
stale copy is the worst possible outcome:

    * every TypeScript test passes, against last week's bytes;
    * every Dart test passes, against this week's;
    * nothing fails until an alert crosses between them, on a handset, in the
      field, where the failure reads as "authentication failed" with no clue
      which of four things diverged.

So: byte-for-byte equality, asserted in CI. The mobile job separately re-runs
the generators and fails on any diff, which together mean the vectors are always
what the current Dart encoder produces AND the console always reads the same
ones.

    python3 scripts/check_vectors_synced.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "test/fixtures"
MIRROR = ROOT / "hq-dashboard-next/src/lib/__fixtures__"

# Vectors the console is expected to hold. Listed rather than globbed: a fixture
# that the console does not use yet should not become a required copy the moment
# somebody adds it, and a fixture that vanishes from this list is a reviewable
# act.
REQUIRED = [
    "sms_alert_vectors.json",
    "mesh_envelope_vectors.json",
]


def main() -> int:
    failures = []

    for name in REQUIRED:
        src = SOURCE / name
        dst = MIRROR / name
        if not src.exists():
            failures.append(
                f"{name}: missing from test/fixtures — regenerate it with "
                f"`flutter test test/gen_*_vectors_test.dart`"
            )
            continue
        if not dst.exists():
            failures.append(
                f"{name}: the console has no copy. Run: cp {src.relative_to(ROOT)} "
                f"{dst.relative_to(ROOT)}/"
            )
            continue
        if src.read_bytes() != dst.read_bytes():
            failures.append(
                f"{name}: the console's copy differs from the Dart-generated one. "
                f"The TypeScript tests are passing against different bytes than "
                f"the app produces. Run: cp {src.relative_to(ROOT)} "
                f"{dst.relative_to(ROOT)}"
            )

    # A vector in the mirror with no source is just as bad: nothing regenerates
    # it, so it silently becomes the only definition of the format.
    for path in sorted(MIRROR.glob("*.json")):
        if not (SOURCE / path.name).exists():
            failures.append(
                f"{path.name}: the console holds a vector file with no generator "
                f"in test/fixtures. Nothing keeps it honest."
            )

    if failures:
        print("Wire-format vectors are out of sync:\n")
        for f in failures:
            print(f"  ✗ {f}")
        print(
            "\nBoth implementations would keep passing their own tests while "
            "disagreeing about real bytes."
        )
        return 1

    print(f"OK: {len(REQUIRED)} vector file(s) identical in both trees.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
