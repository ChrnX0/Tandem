#!/usr/bin/env bash
# Guard: a SQL statement built by string concatenation / interpolation.
# The scar: `"SELECT ... WHERE id = " + userInput` (or an f-string / template
# literal doing the same) is the textbook SQL-injection hole — one `'; DROP TABLE`
# away from disaster. Use parameterized queries / bound params. Medium false-
# positive rate (ORMs, query builders, tagged `sql`` templates), so this is always
# WARN, never FAIL, and tagged-template `sql`...`` is excluded.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
SQL='SELECT[[:space:]].*[[:space:]]FROM[[:space:]]|INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]].*[[:space:]]SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]'  # proofgate-allow
CONCAT='["'"'"'`][[:space:]]*\+|\+[[:space:]]*["'"'"'`]|\$\{|%s|%d|f["'"'"']|\.format[[:space:]]*\(|\|\|[[:space:]]*[[:alnum:]_]'  # proofgate-allow
tab="$(printf '\t')"; n=0
while IFS="$tab" read -r file content; do
  printf '%s' "$content" | grep -Eiq "$SQL"    || continue       # a SQL verb AND
  printf '%s' "$content" | grep -Eq  "$CONCAT"  || continue       # a concat/interp on the same line
  printf '%s' "$content" | grep -Eq  'sql`'     && continue       # tagged template `sql`...`` is safe
  pg_ignored "$(pg_fingerprint sql-concat "$file" "$content")" && continue
  n=$((n + 1))
done < <(pg_added_with_file ':(exclude)*.md' ':(exclude)*test*' ':(exclude)*spec*')
if [ "$n" -gt 0 ]; then
  echo "⚠️  sql-concat: $n added line(s) build SQL by string concat/interpolation — an injection risk. Use parameterized/bound queries. (Query-builder false positive? suppress with proofgate-allow.)"
  exit 2
fi
echo "✅ sql-concat: no hand-concatenated SQL in the diff"
exit 0
