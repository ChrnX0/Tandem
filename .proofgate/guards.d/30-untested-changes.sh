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
# LOCAL ADAPTATION - belongs upstream in ChrnX0/proofgate, because it makes this
# guard blind to every shell project, not only to this one.
#
# Two measured holes, on the diff that produced this comment:
#
#   1. TEST_N required a SLASH before "tests", and `git diff --name-only` emits
#      paths with no leading slash - so "tests/run.sh" did not match, and a diff
#      that added 91 lines of tests was reported as touching zero test files.
#   2. SRC_N counted only language extensions (.ts .py .go ...). Tandem's source
#      is shell, mostly WITHOUT an extension (src/bin/tandem-repair), so the
#      guard saw 1 source file in a diff that changed common.sh, tandem-repair
#      and a new tool.
#
# Both together meant the guard printed a reassuring warning about the wrong
# thing while being incapable of seeing the actual source of this project.
TESTES='(\.test\.|\.spec\.|__tests__|_test\.|(^|/)tests?/)'
SRC_N=$(echo "$CHANGED" | grep -E "($SRC)" | grep -Ev "$TESTES" | grep -Ec '\.(ts|tsx|js|jsx|py|rb|go|rs|java|kt|sh|bash)$|(^|/)[a-z][a-z0-9-]*$' || true)
TEST_N=$(echo "$CHANGED" | grep -Ec "$TESTES" || true)

if [ "${SRC_N:-0}" -gt 0 ] && [ "${TEST_N:-0}" -eq 0 ]; then
  echo "⚠️  untested changes: $SRC_N source file(s) changed, 0 test files touched — is the new behavior pinned by any test?"
  exit 2
fi
echo "✅ tests-changed: $SRC_N source / $TEST_N test file(s) in the diff"
exit 0
