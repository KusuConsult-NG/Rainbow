#!/usr/bin/env python3
"""Refuse any INSERT that would target a generated column.

    ERROR:  428C9: cannot insert a non-DEFAULT value into column "category"
    DETAIL:  Column "category" is a generated column.

`alerts.category` is `GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED`.
PostgreSQL raises 428C9 at PARSE time for any insert whose target column list
contains it — and an insert with NO column list targets every column in ordinal
order, so it names `category` without ever mentioning the word:

    INSERT INTO public.alerts (id, type, category, ...) VALUES (...)  -- named
    INSERT INTO public.alerts SELECT * FROM somewhere                 -- IMPLIED
    INSERT INTO public.alerts VALUES ('...', '...', ...)              -- IMPLIED

The second form is the trap. It is the shape a person reaches for when copying
rows out and back — a backup table, a re-seed, a migration that rebuilds a
table — and it fails the day someone adds a generated column, in a statement
that was correct when it was written and that nothing in the file suggests is
about `category` at all. The failure is total: not a bad row, the whole
statement, every time.

So the rule this enforces is positional, not nominal: an insert into a table
carrying a generated column must have an explicit column list, and that list
must leave the generated columns out. There is no INSERT syntax that skips a
generated column by position, and DEFAULT is the only value it accepts.

The (table, column) pairs are read out of the migrations rather than hardcoded,
so a generated column added later is covered the moment its migration lands.

    python3 scripts/check_generated_column_inserts.py

Exit 0 = every insert in the repository is safe. Non-zero = the file and line.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def strip_noise(sql: str) -> str:
    """Blank out comments and single-quoted literals, preserving line numbers.

    Dollar-quoted bodies are deliberately KEPT: a function body is executable
    SQL and its inserts must be checked. Single-quoted literals are dropped
    because a diagnostic script legitimately carries the forbidden pattern as a
    regex it searches the catalog with — checking that text would flag the tool
    written to find the problem.
    """
    out = []
    i, n = 0, len(sql)
    while i < n:
        two = sql[i:i + 2]
        if two == '--':
            j = sql.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif two == '/*':
            j = sql.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(c if c == '\n' else ' ' for c in sql[i:j]))
            i = j
        elif sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if sql[j + 1:j + 2] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            out.append(''.join(c if c == '\n' else ' ' for c in sql[i:j]))
            i = j
        else:
            out.append(sql[i])
            i += 1
    return ''.join(out)


def generated_columns() -> dict[str, set[str]]:
    """{table: {generated column, ...}} read out of the migration history."""
    found: dict[str, set[str]] = {}
    # `GENERATED ALWAYS AS (` is unambiguous, so find that and read the column
    # name BACKWARDS from it. Reading forwards from a candidate name instead
    # matched `alerts` out of `ALTER TABLE public.alerts ADD COLUMN IF NOT
    # EXISTS category TEXT GENERATED ALWAYS AS (…)`, because `ADD COLUMN IF NOT
    # EXISTS category TEXT` is itself a run of word characters and spaces and
    # so passed for a type name. The check then found no generated column at
    # all and, but for its own guard, would have passed while testing nothing.
    generated = re.compile(r'(?is)\bGENERATED\s+ALWAYS\s+AS\s*\(')
    # The name is whatever follows `ADD COLUMN [IF NOT EXISTS]`, a comma or an
    # opening parenthesis, followed by a type, anchored to the end of the text
    # that precedes `GENERATED` — so the LAST such name wins.
    # The keyword exclusion is not cosmetic. Without it, a multi-column
    # `ALTER TABLE t ADD COLUMN a …, ADD COLUMN b … GENERATED ALWAYS AS (…)`
    # matched at the COMMA — which is further left than `ADD COLUMN`, and
    # leftmost wins — and read the column name as `add`, so the real name never
    # entered the set and an insert naming it would not have been flagged.
    col_before = re.compile(
        r'(?is)(?:ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?|[,(]\s*)'
        r'"?(?!(?:ADD|COLUMN|IF|NOT|EXISTS|CONSTRAINT|PRIMARY|UNIQUE|FOREIGN|CHECK)\b)'
        r'(\w+)"?\s+\w+(?:\s*\([^)]*\))?(?:\s+\w+)*\s*$')
    for path in sorted((REPO / 'supabase' / 'migrations').glob('*.sql')):
        sql = strip_noise(path.read_text(encoding='utf-8'))
        # The table each ALTER/CREATE is talking about, tracked as we walk.
        table = None
        for stmt in sql.split(';'):
            m = re.search(
                r'(?is)\b(?:ALTER|CREATE)\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
                r'(?:public\.)?"?(\w+)"?', stmt)
            if m:
                table = m.group(1).lower()
            if table is None:
                continue
            for g in generated.finditer(stmt):
                # `GENERATED ALWAYS AS IDENTITY` has no parenthesis, so the
                # trailing `(` in the pattern already excludes it; identity
                # columns accept an explicit value under OVERRIDING and are not
                # what 428C9 is about here.
                name = col_before.search(stmt[:g.start()])
                if name:
                    found.setdefault(table, set()).add(name.group(1).lower())
    return found


def insert_targets(sql: str, table: str):
    """Yield (offset, column_list_or_None) for each INSERT INTO <table>."""
    for m in re.finditer(
            r'(?is)\bINSERT\s+INTO\s+(?:public\.)?"?' + re.escape(table) + r'"?\b', sql):
        rest = sql[m.end():]
        head = rest.lstrip()
        if not head.startswith('('):
            yield m.start(), None
            continue
        # Balanced read of the column list.
        start = m.end() + (len(rest) - len(head))
        depth, j = 0, start
        while j < len(sql):
            if sql[j] == '(':
                depth += 1
            elif sql[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield m.start(), sql[start + 1:j]


MARKER = 'generated-column-insert: deliberate'


def deliberate(raw: str, line: int) -> bool:
    """True when the insert is a negative assertion, marked as such.

    `alert_category_behaviour_test.sql` writes a category that contradicts the
    type ON PURPOSE, inside an exception handler, to prove the database refuses
    it — that assertion is the reason the column is GENERATED at all. It has to
    be exempt, but only when the author says so in as many words on one of the
    three lines above it, so an exemption is never something a file acquires by
    accident.
    """
    lines = raw.split('\n')
    return any(MARKER in lines[i] for i in range(max(0, line - 4), min(len(lines), line)))


def count_statements(path: Path) -> int:
    """How many statements a file really holds.

    Counting semicolons with awk said two for a file with one statement: the
    extra was inside the regex literal `'…alerts[^;]{0,100}'`. Comments and
    string literals have to come out first, which strip_noise already does.
    """
    return strip_noise(path.read_text(encoding='utf-8')).count(';')


def dropped_generated() -> set[str]:
    """`table.column` pairs a later migration removes.

    20261018000000 drops the five generated mirrors of geo_*, so after it runs
    `category` is the only generated column on alerts. Without this the rule
    below would still forbid an insert naming `alerts.lga` — harmless, since
    nothing names it, but the message would tell a developer the column is
    generated when it does not exist at all.

    Read from check_schema_convergence.py rather than restated here: that module
    verifies each entry against the migration that claims to drop it, so one
    list is checked and this one cannot drift from it.
    """
    spec = importlib.util.spec_from_file_location(
        'csc', REPO / 'scripts' / 'check_schema_convergence.py')
    csc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(csc)
    return {key.split(':', 1)[1] for key in csc.DROPPED_BY_LATER
            if key.startswith('column:')}


def main() -> int:
    if len(sys.argv) > 2 and sys.argv[1] == '--statements':
        print(count_statements(Path(sys.argv[2])))
        return 0

    gen = generated_columns()
    for pair in dropped_generated():
        table, _, column = pair.partition('.')
        gen.get(table, set()).discard(column)
    gen = {t: cols for t, cols in gen.items() if cols}
    if 'alerts' not in gen or 'category' not in gen.get('alerts', set()):
        # The check is only meaningful if it can still see the column it was
        # written for. A rename that quietly empties the rule would otherwise
        # leave this passing while checking nothing.
        print('✗ no generated column found for public.alerts — has the '
              'migration that creates alerts.category changed shape?',
              file=sys.stderr)
        return 2

    files = sorted(
        list((REPO / 'supabase').rglob('*.sql')) + list((REPO / 'scripts').rglob('*.sql')))
    problems: list[str] = []
    checked = 0

    for path in files:
        raw = path.read_text(encoding='utf-8')
        sql = strip_noise(raw)
        for table, cols in gen.items():
            for offset, collist in insert_targets(sql, table):
                checked += 1
                line = raw.count('\n', 0, offset) + 1
                where = f'{path.relative_to(REPO)}:{line}'
                if deliberate(raw, line):
                    continue
                if collist is None:
                    problems.append(
                        f'{where}: INSERT INTO {table} has NO column list, so it '
                        f'targets every column including '
                        f'{", ".join(sorted(cols))} — PostgreSQL will refuse it '
                        f'with 428C9. Name the columns and leave the generated '
                        f'ones out.')
                    continue
                named = {c.strip().strip('"').lower()
                         for c in collist.split(',')}
                clash = sorted(named & cols)
                if clash:
                    problems.append(
                        f'{where}: INSERT INTO {table} names the generated '
                        f'column(s) {", ".join(clash)} — PostgreSQL will refuse '
                        f'it with 428C9. Remove them; the value is computed.')

    for p in problems:
        print(f'✗ {p}', file=sys.stderr)
    if problems:
        print(f'\n{len(problems)} unsafe insert(s).', file=sys.stderr)
        return 1

    tables = ', '.join(f'{t}.{c}' for t, cs in sorted(gen.items()) for c in sorted(cs))
    print(f'✓ {checked} INSERT(s) checked against generated columns: {tables}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
