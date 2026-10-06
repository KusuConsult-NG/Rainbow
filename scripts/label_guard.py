#!/usr/bin/env python3
"""A verdict-table label must not read as DDL to Supabase's pre-run linter.

Supabase's SQL editor lints the buffer BEFORE running it, and its parser reads
words out of quoted strings as identifiers. A check labelled
"...written into your own channel" made it warn

    This query creates a table without enabling Row Level Security. Clients
    using anon or authenticated keys may be able to access `your`.

about a table that does not exist, and made another path fail with
`42P01: relation "your" does not exist`. Renaming the word moved the warning to
the new word — `into somebody` became `somebody` — which is how the mechanism
became clear: it takes whatever follows `INTO`.

These four are the keywords a relation name follows in real SQL, so they are the
ones a naive parser reads a table name after. An operator cannot tell a parser
quirk from a real finding on a file they are about to paste into production, and
the safe response to not knowing is to stop — so the trigger is banned rather
than explained.

This lived inside build_apply_all.py and guarded only that one script. The other
two generated files are pasted into the same editor and had no guard at all:
bootstrap_staging.sql builds a staging project, and scripts/apply_in_parts/
inherits apply_all's verdict table but prepends text of its own. The rule is the
same for all of them, so it lives in one module and each builder calls it.
"""
from __future__ import annotations

import re
import sys

FORBIDDEN_IN_LABELS = ('into', 'from', 'join', 'table')

# Matches a verdict-table row: four spaces, `(N, '<label>'`. Deliberately
# anchored, so prose elsewhere in the generated SQL is not scanned — only the
# labels that end up inside a quoted string in the result set.
_LABEL = re.compile(r"^    \(\d+, '([^']+)'", re.M)


def check_labels(text: str, where: str = '') -> None:
    """Exit non-zero naming every offending label, or return quietly."""
    bad: list[tuple[str, str]] = []
    for m in _LABEL.finditer(text):
        label = m.group(1)
        for word in FORBIDDEN_IN_LABELS:
            if re.search(rf'\b{word}\b', label, re.I):
                bad.append((word, label))
    if not bad:
        return
    prefix = f'{where}: ' if where else ''
    for word, label in bad:
        print(f"{prefix}label contains '{word}', which Supabase's linter reads "
              f'as DDL: {label!r}', file=sys.stderr)
    raise SystemExit(1)
