#!/usr/bin/env python3
"""Fail if either app reads or writes a column that no migration creates.

WHY THIS EXISTS
---------------
The HQ mass-broadcast screen wrote six columns that existed in no migration —
`target_agency`, `target_sector`, `target_lga`, `target_ward`, `target_pu`,
`active`. PostgREST rejects an insert naming an unknown column *in full*, so
every broadcast HQ ever sent failed, and the operator saw a raw PostgREST
string where a statewide warning should have been. It was found by reading, by
accident, months later.

Nothing about that was hard to detect. A column name is either in the schema or
it is not, and both sides are in this repository. So this checks it on every
push, and the whole class of fault stops being a matter of somebody noticing.

WHAT IT CANNOT SEE
------------------
Production. Columns added by hand in the Supabase dashboard exist there and in
no migration here, so this reports them as drift — which is the correct answer
for a repository that is supposed to be able to rebuild the database, and is
exactly how the `agency_*` tables were found. Fix the drift by writing the
migration, not by adding an exception.

Deliberately conservative: it only reads object literals passed to insert(),
update() and upsert(), and only flags a name when the TABLE is one this
repository creates. An unknown table is reported separately, not as a column
error.

    python3 scripts/check_schema_drift.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS = sorted((ROOT / "supabase/migrations").glob("*.sql"))

COMMENT = re.compile(r"--[^\n]*")

# `CREATE TABLE [IF NOT EXISTS] public.foo ( ... )` — captured to the matching
# close paren by counting depth, since column definitions contain parens too.
CREATE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?([a-z_]+)\s*\(",
    re.IGNORECASE,
)
ADD_COLUMN = re.compile(
    r"ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z_]+)", re.IGNORECASE
)
ALTER_TABLE = re.compile(
    r"ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z_]+)", re.IGNORECASE
)

# Columns every PostgREST caller may legitimately name even though a migration
# never spells them out.
ALWAYS_OK = {"id", "created_at", "updated_at"}


def strip_comments(sql: str) -> str:
    return COMMENT.sub("", sql)


def schema_columns() -> dict[str, set[str]]:
    """table -> set of column names, across every migration in order."""
    tables: dict[str, set[str]] = {}
    for path in MIGRATIONS:
        sql = strip_comments(path.read_text())

        for m in CREATE.finditer(sql):
            table = m.group(1)
            depth, i = 1, m.end()
            while i < len(sql) and depth:
                if sql[i] == "(":
                    depth += 1
                elif sql[i] == ")":
                    depth -= 1
                i += 1
            body = sql[m.end() : i - 1]
            cols = tables.setdefault(table, set())
            # One column per top-level comma; the name is the first token.
            depth = 0
            current = ""
            for ch in body + ",":
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                if ch == "," and depth == 0:
                    token = current.strip().split()
                    if token and token[0].upper() not in {
                        "PRIMARY", "FOREIGN", "UNIQUE", "CHECK", "CONSTRAINT", "EXCLUDE",
                    }:
                        cols.add(token[0].lower())
                    current = ""
                else:
                    current += ch

        # ALTER TABLE x ADD COLUMN a, ADD COLUMN b — the table name is whichever
        # ALTER TABLE most recently preceded each ADD COLUMN.
        for m in ADD_COLUMN.finditer(sql):
            prior = list(ALTER_TABLE.finditer(sql, 0, m.start()))
            if prior:
                tables.setdefault(prior[-1].group(1), set()).add(m.group(1).lower())

    return tables


# ── What the apps write ─────────────────────────────────────────────────────

# What may sit between `from('x')` and the call on it. A character budget was
# the wrong constraint in both directions: 300 was small enough that an
# explanatory comment above a `.select` hid it, and widening to 2000 walked
# into the NEXT `from(` and blamed one table for another's columns. Requiring
# that no other `from(` intervenes is the actual rule.
GAP = r"((?:(?!\bfrom\s*\().)*?)"


# .from('alerts') ... .insert({ ... }) — the call and its literal may be far
# apart and span lines, so the table is tracked separately from the payload.
TS_CALL = re.compile(
    r"from\(\s*['\"]([a-z_]+)['\"]\s*\)" + GAP + r"\.(insert|update|upsert)\s*\(\s*\{",
    re.DOTALL,
)
DART_CALL = re.compile(
    r"from\(\s*['\"]([a-z_]+)['\"]\s*\)" + GAP + r"\.(insert|update|upsert)\s*\(\s*(?:<String,\s*dynamic>)?\s*\{",
    re.DOTALL,
)

# ...but the payload is just as often built first and passed by name:
#
#     const payload = { ... };
#     await supabase.from('system_alerts').insert(payload);
#
# which is EXACTLY the shape of the bug this script exists for. A first version
# only understood inline literals and gave the console a clean bill of health.
TS_CALL_VAR = re.compile(
    r"from\(\s*['\"]([a-z_]+)['\"]\s*\)" + GAP + r"\.(insert|update|upsert)\s*\(\s*([A-Za-z_$][\w$]*)\s*[),]",
    re.DOTALL,
)
DART_CALL_VAR = re.compile(
    r"from\(\s*['\"]([a-z_]+)['\"]\s*\)" + GAP + r"\.(insert|update|upsert)\s*\(\s*([A-Za-z_][\w]*)\s*[),]",
    re.DOTALL,
)
TS_DECL = r"(?:const|let|var)\s+{name}\s*(?::[^=]+)?=\s*\{{"
DART_DECL = r"(?:final|var|const)\s+(?:Map<String,\s*dynamic>\s+)?{name}\s*=\s*(?:<String,\s*dynamic>)?\s*\{{"
TS_KEY = re.compile(
    r"(?:^|[{,])\s*(?:\.\.\.)?([a-z_][a-z0-9_]*)\s*:", re.IGNORECASE | re.MULTILINE
)
DART_KEY = re.compile(
    r"(?:^|[{,])\s*['\"]([a-z_][a-z0-9_]*)['\"]\s*:", re.MULTILINE
)
# A `//` comment between two entries hides the entry after it: the key regex
# anchors on the preceding `{` or `,`, and a comment line sits between them.
# That is not hypothetical — it is why the first version of this script missed
# `alerts.escalation_log` while reporting `alerts.escalated_to_agency` four
# lines above it. An under-reporting gate is worse than none, so comments are
# stripped from a literal before its keys are read.
LINE_COMMENT = re.compile(r"(?<![:'\"])//[^\n]*")


def blank_comments(text: str) -> str:
    """Replace `//` comments with spaces, keeping every offset and line intact.

    Matching runs over this rather than the raw source. A comment between
    `.from('x')` and `.select(...)` otherwise pushes them past the window the
    patterns allow between the two — which is exactly how the read-side check
    first failed to fire: the explanatory comment added above the fixed select
    was itself long enough to hide it.
    """
    return LINE_COMMENT.sub(lambda m: " " * len(m.group(0)), text)


def literal_after(text: str, open_brace: int) -> str:
    """The object literal starting at `open_brace`, to its matching close."""
    depth, i = 1, open_brace + 1
    while i < len(text) and depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[open_brace + 1 : i - 1]


def top_level_keys(text: str, open_brace: int, key_re: re.Pattern[str]) -> list[str]:
    """Column names in the object literal whose `{` is at `open_brace`.

    Only the top level: a nested object is a JSON column's contents, not a set
    of column names.
    """
    body = LINE_COMMENT.sub("", literal_after(text, open_brace))
    depth, top = 0, ""
    for ch in body:
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        if depth == 0:
            top += ch
    return [m.group(1).lower() for m in key_re.finditer(top)]


def written_columns() -> list[tuple[str, str, str, int]]:
    """(table, column, file, line) for every object written to a table."""
    found = []
    sources = [
        (ROOT / "hq-dashboard-next/src", ("*.ts", "*.tsx"), TS_CALL, TS_CALL_VAR, TS_DECL, TS_KEY),
        (ROOT / "lib", ("*.dart",), DART_CALL, DART_CALL_VAR, DART_DECL, DART_KEY),
    ]
    for base, globs, call_re, var_re, decl_tpl, key_re in sources:
        for pattern in globs:
            for path in base.rglob(pattern):
                if path.name.endswith((".test.ts", ".test.tsx", "_test.dart")):
                    continue
                text = blank_comments(path.read_text())
                rel = str(path.relative_to(ROOT))

                # Inline literal: .insert({ ... })
                for m in call_re.finditer(text):
                    line = text.count("\n", 0, m.start()) + 1
                    for col in top_level_keys(text, m.end() - 1, key_re):
                        found.append((m.group(1), col, rel, line))

                # By name: const payload = { ... }; .insert(payload)
                for m in var_re.finditer(text):
                    table, name = m.group(1), m.group(4)
                    decl = re.search(decl_tpl.format(name=re.escape(name)), text)
                    if not decl:
                        continue
                    line = text.count("\n", 0, decl.start()) + 1
                    for col in top_level_keys(text, decl.end() - 1, key_re):
                        found.append((table, col, rel, line))
    return found


# `.select('id, full_name, role')` — a column named here that does not exist
# fails the read the same way a bad write fails: PostgREST rejects the whole
# query. That is how the HQ board's profile map came back empty, leaving every
# officer rendered as `TACTICAL SQUAD #A1B2C3` with nothing logged anywhere.
SELECT_CALL = re.compile(
    r"from\(\s*['\"]([a-z_]+)['\"]\s*\)" + GAP + r"\.select\(\s*['\"]([^'\"]*)['\"]",
    re.DOTALL,
)


def selected_columns() -> list[tuple[str, str, str, int]]:
    """(table, column, file, line) for every explicit select list."""
    found = []
    for base, globs in (
        (ROOT / "hq-dashboard-next/src", ("*.ts", "*.tsx")),
        (ROOT / "lib", ("*.dart",)),
    ):
        for pattern in globs:
            for path in base.rglob(pattern):
                if path.name.endswith((".test.ts", ".test.tsx", "_test.dart")):
                    continue
                text = blank_comments(path.read_text())
                for m in SELECT_CALL.finditer(text):
                    table, cols = m.group(1), m.group(3)
                    # `*`, an embedded resource (`profiles(name)`) or an alias
                    # (`x:y`) — not a plain column list; left alone rather than
                    # guessed at.
                    if "*" in cols or "(" in cols or ":" in cols:
                        continue
                    line = text.count("\n", 0, m.start()) + 1
                    for col in re.findall(r"[a-z_][a-z0-9_]*", cols):
                        found.append(
                            (table, col, str(path.relative_to(ROOT)), line)
                        )
    return found


# `.rpc('resolve_emergency', ...)` — a call to a function no migration defines
# returns 404 from PostgREST and fails the same silent way a bad column does.
# The type argument matters: these are written `.rpc<dynamic>('name', ...)` in
# Dart, and a pattern without it finds nothing while reporting success — which
# is what a first look at this actually did.
RPC_CALL = re.compile(r"\.rpc\s*(?:<[^>]*>)?\s*\(\s*['\"]([a-z_][a-z0-9_]*)['\"]")

# CREATE [OR REPLACE] FUNCTION public.name(
FUNCTION_DEF = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z_][a-z0-9_]*)",
    re.IGNORECASE,
)


def defined_functions() -> set[str]:
    names: set[str] = set()
    for path in MIGRATIONS:
        names.update(
            m.group(1).lower()
            for m in FUNCTION_DEF.finditer(strip_comments(path.read_text()))
        )
    return names


def called_functions() -> list[tuple[str, str, int]]:
    """(function, file, line) for every .rpc() call."""
    found = []
    for base, globs in (
        (ROOT / "hq-dashboard-next/src", ("*.ts", "*.tsx")),
        (ROOT / "lib", ("*.dart",)),
    ):
        for pattern in globs:
            for path in base.rglob(pattern):
                if path.name.endswith((".test.ts", ".test.tsx", "_test.dart")):
                    continue
                text = blank_comments(path.read_text())
                for m in RPC_CALL.finditer(text):
                    found.append(
                        (
                            m.group(1),
                            str(path.relative_to(ROOT)),
                            text.count("\n", 0, m.start()) + 1,
                        )
                    )
    return found


def main() -> int:
    schema = schema_columns()
    problems: list[str] = []
    unknown_tables: set[str] = set()

    for table, column, path, line in sorted(set(selected_columns())):
        if table not in schema:
            unknown_tables.add(table)
            continue
        if column in ALWAYS_OK or column in schema[table]:
            continue
        problems.append(f"  {path}:{line}  {table}.{column}   (selected)")

    for table, column, path, line in sorted(set(written_columns())):
        if table not in schema:
            unknown_tables.add(table)
            continue
        if column in ALWAYS_OK or column in schema[table]:
            continue
        problems.append(f"  {path}:{line}  {table}.{column}")

    if unknown_tables:
        print("Tables written to that no migration creates:")
        for t in sorted(unknown_tables):
            print(f"  {t}")
        print()

    functions = defined_functions()
    missing_fns = [
        f"  {path}:{line}  {fn}()"
        for fn, path, line in sorted(set(called_functions()))
        if fn not in functions
    ]
    if missing_fns:
        print("RPC functions called that no migration defines:")
        print("\n".join(missing_fns))
        print()
        print("PostgREST answers 404 for an undefined function, so each of these")
        print("fails at runtime and nowhere else.")
        print()

    if problems:
        print("Columns read or written that no migration creates:")
        print("\n".join(sorted(set(problems))))
        print()
        print("PostgREST rejects a query naming an unknown column IN FULL — a")
        print("select as much as an insert — so each of these fails at runtime")
        print("and nowhere else. Add the column in a migration, or stop naming it.")
        return 1

    if unknown_tables or missing_fns:
        return 1

    print(f"OK: every column read or written by either app exists in the "
          f"schema ({len(schema)} tables), and all "
          f"{len(set(f for f, _, _ in called_functions()))} RPC functions "
          f"called are defined.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
