#!/usr/bin/env bash
# Guard: a constraint added to an existing table's CREATE TABLE, with no migration.
# The scar: a column's domain was tightened with `check (sex in ('M','F'))` inside a
# `create table if not exists`, the schema files were declared converged, and every
# gate went green — schema-parity, generated-types, the lot. The constraint protected
# nothing: on any database that already had the table (production, every tenant, every
# restore) `if not exists` is a no-op, so the DDL never ran. The bad data that caused
# the scar would have been accepted again. A constraint only reaches a live database
# through a MIGRATION.
#
# WARN, never FAIL: migrations live in wildly different places per project (a
# migrations/ directory, an ALTER list in code, a framework's own DSL), so this cannot
# be decided with certainty — it asks the question rather than blocking the delivery.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"

# A constraint being ADDED: check / unique / not null / foreign key, in a SQL-ish file.
CONSTRAINT='(^|[[:space:],(])(check[[:space:]]*\(|unique[[:space:]]*\(|not[[:space:]]+null|references[[:space:]]|foreign[[:space:]]+key)'  # proofgate-allow
# Evidence that the same delivery also migrates: an ALTER, or a migration file path.
MIGRATION='alter[[:space:]]+table|add[[:space:]]+constraint|migrat|__migration'  # proofgate-allow

tab="$(printf '\t')"; n=0; files=""
while IFS="$tab" read -r file content; do
  # Only files that look like a schema definition — not application code.
  printf '%s' "$file" | grep -Eiq '\.(sql|ddl)$|schema|migration' || continue
  printf '%s' "$content" | grep -Eiq "$CONSTRAINT" || continue
  # A brand-new table is fine: nothing exists yet, so CREATE TABLE carries it.
  # Only an EXISTING table's create block is the trap, and `if not exists` is its tell.
  git diff "$BASE"..HEAD -- "$file" | grep -Eiq 'create[[:space:]]+table[[:space:]]+if[[:space:]]+not[[:space:]]+exists' || continue
  pg_ignored "$(pg_fingerprint schema-constraint-no-migration "$file" "$content")" && continue
  n=$((n + 1))
  case " $files " in *" $file "*) ;; *) files="$files $file" ;; esac
done < <(pg_added_with_file)

[ "$n" -gt 0 ] || { echo "✅ schema-constraint-no-migration: no constraint added to an if-not-exists table"; exit 0; }

# It only counts as migrated if the SAME delivery ships the ALTER.
if git diff "$BASE"..HEAD | grep -E '^\+' | grep -Eiq "$MIGRATION"; then
  echo "✅ schema-constraint-no-migration: $n constraint line(s) ship with a migration"
  exit 0
fi

echo "⚠️  schema-constraint-no-migration: $n constraint line(s) added inside a \`create table if not exists\` with NO migration in this diff —$files"
echo "    On a database that already has the table, \`if not exists\` is a no-op: the constraint never runs, and every schema check still goes green."
echo "    Ship the matching \`alter table ... add constraint\` (guarded so it is idempotent), or suppress with proofgate-allow if this table is genuinely new."
exit 2
