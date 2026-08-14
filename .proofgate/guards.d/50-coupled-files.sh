#!/usr/bin/env bash
# Guard: coupled files — pairs that must change together (ORM schema ↔ SQL mirror,
# API contract ↔ client types, i18n keys ↔ translations). One side moving alone
# is silent drift you'll only meet in production.
# Configure: proofgate.json → "coupledFiles": [{ "a": "...", "b": "...", "reason": "..." }]
# Exit: 0 = clean/skipped · 2 = WARN.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"

N="$(cfg_len '.coupledFiles')"
[ "${N:-0}" -gt 0 ] || { echo "✅ coupled-files: no pairs configured — guard skipped"; exit 0; }

CHANGED="$(git diff --name-only "$BASE"..HEAD)"
DRIFT=0
for i in $(seq 0 $((N - 1))); do
  A="$(cfg ".coupledFiles[$i].a")"; B="$(cfg ".coupledFiles[$i].b")"
  R="$(cfg ".coupledFiles[$i].reason")"; R="${R:-they must move together}"
  A_CH=$(echo "$CHANGED" | grep -cx "$A" || true); B_CH=$(echo "$CHANGED" | grep -cx "$B" || true)
  if [ "$A_CH" != "$B_CH" ]; then
    echo "⚠️  coupled-files: $A and $B did NOT change together ($R)"
    DRIFT=$((DRIFT + 1))
  fi
done

[ "$DRIFT" -gt 0 ] && exit 2
echo "✅ coupled-files: all $N configured pair(s) moved together (or stayed still)"
exit 0
