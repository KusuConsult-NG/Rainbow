#!/usr/bin/env python3
"""Assert the offline channels' randomness comes from the platform CSPRNG.

WHY THIS GATE EXISTS
--------------------
It was written the day it caught something. `mesh_sealer.dart` shipped with

    final entropy = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < seed.length; i++) { seed[i] = ...entropy...; }

as the seed for the generator that produces (a) every AES-GCM nonce the mesh
uses and (b) HQ's own keypair. Two failures, both severe and both invisible in
any test that only checks "does it decrypt":

  * Two seals in the same microsecond seed the generator identically and emit
    the SAME nonce under the same derived key. A repeated GCM nonce leaks the
    XOR of the two plaintexts and the authentication subkey — it is enough to
    forge, not merely to weaken.
  * A keypair whose entropy is the time of day has a searchable keyspace, and
    that key opens every mesh alert ever sent, past ones included.

Nothing about the ciphertext looks wrong when this is the case, so no behaviour
test finds it. A reading gate does, and unlike a review it happens every time.

THE RULE
--------
Inside the crypto directories:

  * a clock (`*SinceEpoch`, `DateTime.now()`) must not appear near the seeding of
    a generator;
  * `Random()` — the non-cryptographic one — must not be constructed at all.
    `Random.secure()` or an injected instance, or nothing.

Timestamps themselves are fine and necessary: an alert carries when the phone
raised it. It is timestamps AS ENTROPY that this refuses.

    python3 scripts/check_crypto_entropy.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Where key material and nonces are produced.
CRYPTO_DIRS = ["lib/core/mesh", "lib/core/offline"]

SEEDING = re.compile(r"FortunaRandom\(\)|\.seed\(|KeyParameter\(seed|nextBytes\(")
CLOCK = re.compile(r"SinceEpoch|DateTime\.now\(\)")
# `Random(` but not `Random.secure(`, and not a type annotation like `Random? r`.
WEAK_RANDOM = re.compile(r"(?<!\.)\bRandom\(")

# How many lines count as "near". A seed built in a loop is a handful of lines.
WINDOW = 8


def main() -> int:
    failures = []

    for rel in CRYPTO_DIRS:
        base = ROOT / rel
        if not base.exists():
            failures.append(f"{rel}: no such directory — did it move?")
            continue

        for path in sorted(base.rglob("*.dart")):
            lines = path.read_text().splitlines()
            code = [
                "" if line.lstrip().startswith(("//", "///", "*")) else line
                for line in lines
            ]

            seeding_at = [i for i, line in enumerate(code) if SEEDING.search(line)]
            for i in seeding_at:
                lo, hi = max(0, i - WINDOW), min(len(code), i + WINDOW + 1)
                for j in range(lo, hi):
                    if CLOCK.search(code[j]):
                        failures.append(
                            f"{path.relative_to(ROOT)}:{j + 1}: a clock is being "
                            f"used as entropy near the seeding on line {i + 1}. "
                            f"Use Random.secure()."
                        )

            for i, line in enumerate(code):
                if WEAK_RANDOM.search(line):
                    failures.append(
                        f"{path.relative_to(ROOT)}:{i + 1}: Random() is not "
                        f"cryptographic. Use Random.secure(), or take one as a "
                        f"parameter so tests can inject a fixed sequence."
                    )

    if failures:
        print("Crypto entropy check FAILED:\n")
        for f in failures:
            print(f"  ✗ {f}")
        print(
            "\nNothing about the resulting ciphertext looks wrong, which is why "
            "this is a reading gate and not a test."
        )
        return 1

    print(f"OK: no clock-derived or non-cryptographic randomness in {len(CRYPTO_DIRS)} "
          f"crypto director{'y' if len(CRYPTO_DIRS) == 1 else 'ies'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
