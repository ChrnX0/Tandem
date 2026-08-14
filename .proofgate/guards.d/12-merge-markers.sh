#!/usr/bin/env bash
# Guard: unresolved merge-conflict markers committed into the diff.
# The scar: a `<<<<<<< HEAD` block shipped to a branch compiles in some languages
# (it sits inside a string/comment) and detonates at runtime; in most it breaks the
# build outright — either way it is the loudest possible "nobody read the diff".
# Deliberately NOT bare `=======`: that is a legal Markdown H1 underline / RST rule,
# a guaranteed false positive. We match only the opening/closing/base markers.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
n="$(pg_scan merge-markers '^(<{7}|>{7}|\|{7})([ 	]|$)' | pg_count)"   # proofgate-allow
if [ "${n:-0}" -gt 0 ]; then
  echo "❌ merge-markers: $n added line(s) carry unresolved conflict markers — resolve the merge before shipping."
  exit 1
fi
echo "✅ merge-markers: none in the diff"
exit 0
