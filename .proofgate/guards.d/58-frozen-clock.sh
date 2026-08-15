#!/usr/bin/env bash
# Guard: a test that reads the real wall clock.
# The scar (lived, more than once): a test that pays a "June" invoice with a real
# `paga_em = now()` passes green in June and turns red on July 1st — a time bomb
# that fails for whoever runs CI next month, not for whoever wrote it. Boundary
# cases are worse: a rate-limit test bucketed by `floor(now/60s)` flakes only when
# a slow step crosses the minute. Tests must FREEZE the clock. Fires only inside
# test files, on the naked now-reading calls.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
PAT='new Date\([[:space:]]*\)|\bDate\.now[[:space:]]*\(|\bdatetime\.(now|today|utcnow)[[:space:]]*\(|\btime\.time[[:space:]]*\(|\bTime\.now\b|time\.Now\(\)'  # proofgate-allow
# Only test files (the pattern is normal in product code, which legitimately reads the clock).
tab="$(printf '\t')"; n=0
while IFS="$tab" read -r file content; do
  case "$file" in *test*|*spec*) ;; *) continue ;; esac
  printf '%s' "$content" | grep -Eq "$PAT" || continue
  pg_ignored "$(pg_fingerprint frozen-clock "$file" "$content")" && continue
  n=$((n + 1))
done < <(pg_added_with_file ':(exclude)*.md')
if [ "${n:-0}" -gt 0 ]; then
  echo "⚠️  frozen-clock: $n added line(s) read the real clock inside a test (new Date()/Date.now()/datetime.now()/time.time()). Freeze it (fake timers / fixed instant) or you're shipping a time bomb."
  exit 2
fi
echo "✅ frozen-clock: tests don't read the wall clock"
exit 0
