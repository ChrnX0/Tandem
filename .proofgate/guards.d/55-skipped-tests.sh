#!/usr/bin/env bash
# Guard: a test disabled in the diff.
# The scar: `.skip` / `xit` / `@pytest.mark.skip` / `#[ignore]` gets added "just to
# get CI green for now" and never comes back — the suite is green and a lie. This
# is the quieter sibling of debug-leftovers' `.only`: `.only` silences the OTHER
# tests, `.skip` silences THIS one. Both mean green ≠ covered.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
PAT='\.skip[[:space:]]*\(|\bxit[[:space:]]*\(|\bxdescribe[[:space:]]*\(|@pytest\.mark\.skip|@unittest\.skip|#\[ignore\]|\bt\.Skip[[:space:]]*\(|\bit\.skip\b|\btest\.skip\b'  # proofgate-allow
n="$(pg_scan skipped-tests "$PAT" ':(exclude)*.md' | pg_count)"
if [ "${n:-0}" -gt 0 ]; then
  echo "⚠️  skipped-tests: $n added line(s) disable a test (.skip/xit/@skip/#[ignore]/t.Skip). Green CI now hides this case — re-enable or delete it, don't mute it."
  exit 2
fi
echo "✅ skipped-tests: no tests muted in the diff"
exit 0
