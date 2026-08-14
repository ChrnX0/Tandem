#!/usr/bin/env bash
# Guard: secrets added in the diff (API keys, tokens, private keys).
# A leaked credential is the single most expensive line of code you can ship.
# High-signal provider patterns are a hard FAIL. A generic `token = "…"` assignment
# is a WARN (real config sometimes looks like this). False positive? Two escape
# hatches: a `proofgate-allow` comment on the line, or a `secretAllowlist` regex in
# proofgate.json (e.g. a well-known test token). Exit: 0 = clean · 1 = FAIL · 2 = WARN.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"

# High-signal provider shapes (low false-positive by design) → FAIL.
PATTERNS='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|sk_live_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJhbGciOi[A-Za-z0-9_-]{20,}\.'  # proofgate-allow
# Generic "assign a long opaque value to a secret-named field" → WARN.
GENERIC='(api[_-]?key|apikey|secret|token|passwd|password|client[_-]?secret|access[_-]?token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/_=-]{20,}["'"'"']'  # proofgate-allow
# Placeholder values that only LOOK like secrets → never flag.
PLACEHOLDER='example|sample|placeholder|changeme|change-me|your[_-]|dummy|redacted|xxx+|\.\.\.|<[a-z]|\$\{|process\.env|os\.environ|import\.meta'

DIFF() { git diff "$BASE"..HEAD -- . \
  ':(exclude)*.lock' ':(exclude)*lock.yaml' ':(exclude)*lock.json' \
  ':(exclude)*.env.example' ':(exclude)*.env.sample' "${PG_SELF_EXCLUDE[@]}" 2>/dev/null \
  | grep -E '^\+' | grep -v 'proofgate-allow'; }

# Apply a user allowlist of regexes (each line is a pattern to drop).
ALLOW="$(cfg_list '.secretAllowlist')"
filter_allow() {
  if [ -z "$ALLOW" ]; then cat; return; fi
  local rx; rx="$(printf '%s' "$ALLOW" | paste -sd '|' - 2>/dev/null)"
  [ -n "$rx" ] && grep -Ev -- "$rx" || cat
}

FAIL_HITS=$(DIFF | filter_allow | grep -Ec "$PATTERNS" || true)
if [ "${FAIL_HITS:-0}" -gt 0 ]; then
  echo "❌ secrets: $FAIL_HITS added line(s) look like credentials (API key/token/private key). Remove and ROTATE them — a pushed secret is a burned secret."
  DIFF | filter_allow | grep -E "$PATTERNS" | sed -E 's/^(.{60}).*/     \1…/' | head -5
  exit 1
fi

WARN_HITS=$(DIFF | filter_allow | grep -Ei "$GENERIC" | grep -Eiv "$PLACEHOLDER" | grep -c . || true)
if [ "${WARN_HITS:-0}" -gt 0 ]; then
  echo "⚠️  secrets: $WARN_HITS added line(s) assign a long opaque value to a secret-named field — if that's a real credential, move it to an env var. (Test fixture? proofgate-allow or secretAllowlist.)"
  exit 2
fi
echo "✅ secrets: no credential-shaped lines added in the diff"
exit 0
