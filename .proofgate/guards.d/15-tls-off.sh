#!/usr/bin/env bash
# Guard: TLS/certificate verification disabled in the diff.
# The scar: "just make the cert error go away" ships `rejectUnauthorized: false`
# to production and every HTTPS call it makes is now a silent MITM waiting to
# happen. Code-level disables are a hard FAIL. A `curl -k` in a shell script is a
# WARN, not a FAIL: self-signed local/dev scripts use it legitimately, and one
# wrong ❌ per week is how a gate gets aliased to `true` (bypass culture).
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true

# Code-level disables (exclude test/spec/fixture files + markdown — they demo it).
CODE='rejectUnauthorized[[:space:]]*:[[:space:]]*false|verify[[:space:]]*=[[:space:]]*False|InsecureSkipVerify[[:space:]]*:[[:space:]]*true|NODE_TLS_REJECT_UNAUTHORIZED[[:space:]]*[:=][[:space:]]*.?0|CURLOPT_SSL_VERIFYPEER[[:space:]]*,[[:space:]]*(0|false)|ssl[._]?verify[[:space:]]*[:=][[:space:]]*(false|no|0)'  # proofgate-allow
EXCL=':(exclude)*test*' ; EXCL2=':(exclude)*spec*'; EXCL3=':(exclude)*fixture*'; EXCL4=':(exclude)*.md'
code_n="$(pg_scan tls-off "$CODE" "$EXCL" "$EXCL2" "$EXCL3" "$EXCL4" | pg_count)"

# curl -k / --insecure → WARN.
curl_n="$(pg_scan tls-off 'curl([[:space:]]+-[[:alnum:]]*k|[[:space:]]+--insecure)' ':(exclude)*.md' | pg_count)"  # proofgate-allow

if [ "${code_n:-0}" -gt 0 ]; then
  echo "❌ tls-off: $code_n added line(s) DISABLE TLS/cert verification in code — every HTTPS call becomes MITM-able. Remove it."
  exit 1
fi
if [ "${curl_n:-0}" -gt 0 ]; then
  echo "⚠️  tls-off: $curl_n added line(s) run curl with -k/--insecure — fine for local self-signed, dangerous against real hosts. Justify it."
  exit 2
fi
echo "✅ tls-off: TLS verification left intact"
exit 0
