#!/usr/bin/env bash
# Guard: an error swallowed on the same line it is caught.
# The scar: `catch (e) {}` / `except: pass` / `rescue nil` on a money, auth, or
# write path turns a real failure into a green screen — the payment silently
# didn't go through, the token silently didn't rotate, and you find out from the
# user. This flags only the SINGLE-LINE empty handler (the deliberate mute); a
# multi-line body with real handling is out of scope.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
PAT='catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|except[^:]*:[[:space:]]*pass[[:space:]]*$|rescue[[:space:]]+nil[[:space:]]*$|rescue[[:space:]]*=>[[:space:]]*[[:alnum:]_]+[[:space:]]*$'  # proofgate-allow
n="$(pg_scan silent-catch "$PAT" ':(exclude)*.md' | pg_count)"
if [ "${n:-0}" -gt 0 ]; then
  echo "⚠️  silent-catch: $n added line(s) swallow an error with no handling (empty catch / except: pass / rescue nil). On a money/auth/write path this hides real failures — handle or log it."
  exit 2
fi
echo "✅ silent-catch: no muted error handlers added"
exit 0
