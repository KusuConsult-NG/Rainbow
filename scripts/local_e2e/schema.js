/**
 * The column set of every public table, read out of `supabase/migrations/`.
 *
 * This exists so the local fake can reject an unknown column the way PostgREST
 * does — in full, with a 400, taking the whole query with it. That behaviour is
 * the root of an entire defect class in this system (a broadcast screen writing
 * six columns that did not exist, an escalation writing two more, a profile
 * lookup selecting three), and a fake that quietly tolerates the unknown column
 * would hide exactly the bug the run is meant to catch.
 *
 * `scripts/check_schema_drift.py` gates the same thing statically, from the
 * source. This gates it from the running browser, which is a different and
 * complementary claim: not "the code mentions a bad column" but "the app, in
 * use, asked for one".
 */

const fs = require('fs');
const path = require('path');

const MIGRATIONS = path.join(__dirname, '..', '..', 'supabase', 'migrations');

/** Strip `--` line comments and block comments without shifting anything else. */
function decomment(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--[^\n]*/g, '');
}

/** Split a parenthesised column list on top-level commas only. */
function splitTopLevel(body) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of body) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) {
      out.push(cur);
      cur = '';
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out;
}

const NON_COLUMN = /^(constraint|primary|unique|foreign|check|exclude|like|inherits)\b/i;

function build() {
  const tables = new Map();
  /** table -> set of tables it declares a foreign key to. */
  const refs = new Map();
  const add = (table, column) => {
    if (!table || !column) return;
    if (!tables.has(table)) tables.set(table, new Set());
    tables.get(table).add(column);
  };
  const addRef = (from, to) => {
    if (!from || !to) return;
    if (!refs.has(from)) refs.set(from, new Set());
    refs.get(from).add(to);
  };

  const files = fs.readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const sql = decomment(fs.readFileSync(path.join(MIGRATIONS, file), 'utf8'));

    // create table [if not exists] [public.]name ( ... );
    const createRe = /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;
    let m;
    while ((m = createRe.exec(sql)) !== null) {
      const table = m[1];
      // Walk forward to the matching close paren.
      let i = createRe.lastIndex;
      let depth = 1;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '(') depth++;
        else if (sql[i] === ')') depth--;
        i++;
      }
      const body = sql.slice(createRe.lastIndex, i - 1);
      for (const part of splitTopLevel(body)) {
        const t = part.trim();
        // A foreign key is what PostgREST needs before it will embed one
        // resource in another's select. Record it either way — inline on the
        // column, or as a table-level constraint.
        const ref = t.match(/references\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?/i);
        if (ref) addRef(table, ref[1]);
        if (!t || NON_COLUMN.test(t)) continue;
        const col = t.match(/^"?([a-z_][a-z0-9_]*)"?/i);
        if (col) add(table, col[1]);
      }
    }

    // alter table [public.]name add column [if not exists] col type [, add column ...]
    //
    // The comma form matters: `ADD COLUMN a TEXT, ADD COLUMN b JSONB` is how
    // most of this repository's migrations are written, and reading only the
    // first clause silently loses every column after it. That mistake made this
    // parser report `alerts.escalation_log` as non-existent, which in turn made
    // the agency portal look broken when it was not.
    const alterRe =
      /alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+((?:[^;])*?);/gi;
    while ((m = alterRe.exec(sql)) !== null) {
      const table = m[1];
      const addRe = /add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gi;
      let a;
      while ((a = addRe.exec(m[2])) !== null) add(table, a[1]);
    }

    // alter table ... rename column a to b
    const renameRe =
      /alter\s+table\s+(?:if\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+rename\s+column\s+"?([a-z_][a-z0-9_]*)"?\s+to\s+"?([a-z_][a-z0-9_]*)"?/gi;
    while ((m = renameRe.exec(sql)) !== null) {
      const set = tables.get(m[1]);
      if (set) {
        set.delete(m[2]);
        set.add(m[3]);
      }
    }
  }

  const columns = {};
  for (const [table, cols] of tables) columns[table] = [...cols].sort();
  const relationships = {};
  for (const [table, to] of refs) relationships[table] = [...to].sort();
  return { columns, relationships };
}

module.exports = { build };

if (require.main === module) {
  const { columns, relationships } = build();
  for (const t of Object.keys(columns).sort()) {
    console.log(`${t} (${columns[t].length}): ${columns[t].join(', ')}`);
  }
  console.log('\nforeign keys:');
  for (const t of Object.keys(relationships).sort()) {
    console.log(`  ${t} -> ${relationships[t].join(', ')}`);
  }
}
