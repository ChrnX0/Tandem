#!/usr/bin/env bash
# Guard: money handled as a floating-point number.
# The scar: `price = parseFloat(...)` / `total: float` / `amount.toFixed(2)` as the
# source of truth means 0.1 + 0.2 = 0.30000000000000004 in someone's invoice, and
# rounding drift that "loses" a cent per transaction until the ledger won't
# reconcile. Money must be an integer in the smallest unit (cents). This is the
# noisiest guard by design (`.toFixed` for DISPLAY is fine) — always WARN, never
# FAIL, and `moneyTerms` in proofgate.json tunes the vocabulary.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
TERMS="$(cfg '.moneyTerms')"; TERMS="${TERMS:-price|amount|total|balance|money|currency|cents|salary|payment|invoice|refund|fee|cost}"
FLOAT='parseFloat[[:space:]]*\(|\.toFixed[[:space:]]*\(|(^|[^[:alnum:]_])float[[:space:]]*\(|:[[:space:]]*float\b|\bf32\b|\bf64\b|(^|[^[:alnum:]_])double[[:space:]]+[[:alnum:]_]*(price|amount|total|balance|money|cost|fee)'  # proofgate-allow
tab="$(printf '\t')"; n=0
while IFS="$tab" read -r file content; do
  printf '%s' "$content" | grep -Eiq "$TERMS" || continue        # a money word AND
  printf '%s' "$content" | grep -Eq "$FLOAT"  || continue        # a float operation, same line
  pg_ignored "$(pg_fingerprint float-money "$file" "$content")" && continue
  n=$((n + 1))
done < <(pg_added_with_file ':(exclude)*.md' ':(exclude)*test*' ':(exclude)*spec*')
if [ "$n" -gt 0 ]; then
  echo "⚠️  float-money: $n added line(s) put money through a float (parseFloat/.toFixed/float/double next to a money word). Store and compute money as integer cents — floats lose pennies. (Display formatting is fine; suppress with proofgate-allow if so.)"
  exit 2
fi
echo "✅ float-money: no money-as-float in the diff"
exit 0
