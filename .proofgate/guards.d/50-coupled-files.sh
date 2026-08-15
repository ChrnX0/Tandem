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
  # LOCAL ADAPTATION - belongs upstream in ChrnX0/proofgate.
  #
  # Some couplings are genuinely one-directional, and forcing them to be
  # symmetric is what makes a guard get ignored. "src/lib/winedeps.sh implies
  # tests/run.sh" is real: changing the DLL->verb table without a test is
  # walking without the auditor, and that table has already had six errors that
  # installed the wrong thing. The converse is not real at all - almost every
  # commit in this repository touches tests/run.sh - so the symmetric form
  # printed this warning on nearly every delivery, about the harmless
  # direction. A warning that is nearly always noise is a warning nobody reads,
  # which is exactly how the one that matters goes unread. Same lesson as the
  # badge guard that blocked a good release: a guard that cries on a healthy
  # diff is worse than the drift it was written for.
  #
  # "direction": "a-implies-b" opts a pair into the one-way check. Absent, the
  # behaviour is the symmetric one, unchanged.
  DIR="$(cfg ".coupledFiles[$i].direction")"
  if [ "$DIR" = "a-implies-b" ]; then
    if [ "$A_CH" -gt 0 ] && [ "$B_CH" -eq 0 ]; then
      echo "⚠️  coupled-files: $A changed and $B did not ($R)"
      DRIFT=$((DRIFT + 1))
    fi
  elif [ "$A_CH" != "$B_CH" ]; then
    echo "⚠️  coupled-files: $A and $B did NOT change together ($R)"
    DRIFT=$((DRIFT + 1))
  fi
done

[ "$DRIFT" -gt 0 ] && exit 2
echo "✅ coupled-files: all $N configured pair(s) moved together (or stayed still)"
exit 0
