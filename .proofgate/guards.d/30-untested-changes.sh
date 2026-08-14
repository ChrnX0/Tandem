#!/usr/bin/env bash
# Guard: source changed, zero test files changed.
# Not every diff needs new tests — but "none of them do" is how regressions ship.
# Source dirs configurable: proofgate.json → "sourceGlobs" (default "src/|lib/|app/").
# Exit: 0 = clean · 2 = WARN.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"

SRC="$(cfg '.sourceGlobs')"; SRC="${SRC:-src/|lib/|app/}"

CHANGED="$(git diff --name-only "$BASE"..HEAD | grep -Ev '(guards\.d/|/\.proofgate/|^\.proofgate/|scripts/verify\.sh|scripts/lib\.sh)')"
SRC_N=$(echo "$CHANGED" | grep -E "($SRC)" | grep -Ev '(\.test\.|\.spec\.|__tests__|_test\.|/tests?/)' | grep -Ec '\.(ts|tsx|js|jsx|py|rb|go|rs|java|kt)$' || true)
TEST_N=$(echo "$CHANGED" | grep -Ec '(\.test\.|\.spec\.|__tests__|_test\.|/tests?/)' || true)

if [ "${SRC_N:-0}" -gt 0 ] && [ "${TEST_N:-0}" -eq 0 ]; then
  echo "⚠️  untested changes: $SRC_N source file(s) changed, 0 test files touched — is the new behavior pinned by any test?"
  exit 2
fi
echo "✅ tests-changed: $SRC_N source / $TEST_N test file(s) in the diff"
exit 0
