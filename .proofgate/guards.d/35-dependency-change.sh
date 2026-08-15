#!/usr/bin/env bash
# Guard: a dependency manifest changed but its lockfile did not.
# The scar: adding a dep to package.json / Cargo.toml / go.mod without committing
# the updated lockfile means CI resolves a DIFFERENT version than you tested —
# "works on my machine" shipped as a diff. (We flag only the lockfile-drift half;
# warning on every dependency bump would be pure noise — teams that want the
# "justify every new dep" behavior can raise this guard's severity in config.)
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"
CHANGED="$(git diff --name-only "$BASE"..HEAD 2>/dev/null)"

# "manifest|lock1 lock2 ..." — any one lock present in the diff clears the manifest.
PAIRS='package.json|pnpm-lock.yaml package-lock.json yarn.lock bun.lockb bun.lock npm-shrinkwrap.json
Cargo.toml|Cargo.lock
go.mod|go.sum
pyproject.toml|poetry.lock uv.lock pdm.lock
Gemfile|Gemfile.lock
composer.json|composer.lock
mix.exs|mix.lock'

drift=""
while IFS='|' read -r manifest locks; do
  [ -n "$manifest" ] || continue
  mpath="$(echo "$CHANGED" | grep -E "(^|/)$manifest\$" | head -1)"
  [ -n "$mpath" ] || continue
  # Was a dependency-shaped line actually ADDED to the manifest? (version specifier present)
  hits="$(git diff "$BASE"..HEAD -- "$mpath" 2>/dev/null | grep -E '^\+' | grep -Ec '[">=~^]|require |gem |implementation ' || true)"
  [ "${hits:-0}" -gt 0 ] || continue
  cleared=""
  for l in $locks; do echo "$CHANGED" | grep -Eq "(^|/)$l\$" && { cleared=1; break; }; done
  [ -z "$cleared" ] && drift="$drift $manifest"
done <<EOF
$PAIRS
EOF

drift="$(printf '%s' "$drift" | sed 's/^ //')"
if [ -n "$drift" ]; then
  echo "⚠️  dependency-change: manifest changed without its lockfile ($drift) — CI will resolve versions you never tested. Commit the updated lockfile."
  exit 2
fi
echo "✅ dependency-change: manifests and lockfiles moved together"
exit 0
