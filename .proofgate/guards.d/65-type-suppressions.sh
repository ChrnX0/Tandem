#!/usr/bin/env bash
# Guard: a type/lint/security check silenced in the diff.
# The scar: `@ts-ignore`, `# type: ignore`, `eslint-disable`, `# noqa`, `#nosec`
# are how a real error gets buried instead of fixed — the next reader trusts the
# green and the bug rides along. Deliberately NOT `@ts-expect-error`: that one
# FAILS if the error stops happening, so it is self-cleaning good practice, not a
# mute. WARN, because there are legitimate uses — but each one owes a justification.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
PAT='@ts-ignore|@ts-nocheck|eslint-disable|#[[:space:]]*type:[[:space:]]*ignore|#[[:space:]]*noqa|#[[:space:]]*nosec|//[[:space:]]*nolint|@SuppressWarnings'  # proofgate-allow
n="$(pg_scan type-suppressions "$PAT" ':(exclude)*.md' | pg_count)"
if [ "${n:-0}" -gt 0 ]; then
  echo "⚠️  type-suppressions: $n added line(s) silence a type/lint/security check (@ts-ignore/type: ignore/eslint-disable/noqa/nosec). Fix the cause or justify each — @ts-expect-error is the self-cleaning alternative."
  exit 2
fi
echo "✅ type-suppressions: no checks silenced in the diff"
exit 0
