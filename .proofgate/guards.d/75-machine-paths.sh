#!/usr/bin/env bash
# Guard: a hard-coded local machine path in the diff.
# The scar: `/home/alice/project/...` or `/Users/bob/...` or `C:\Users\...` baked
# into code or config works on exactly one laptop and breaks in CI, in the
# container, and for every teammate. WARN. Container-idiom users (node/app/runner/
# deploy/…) and Dockerfiles/CI workflows are excluded — those paths are legitimate.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
PAT='/home/[a-z_][a-z0-9_-]*/|/Users/[^/[:space:]"'"'"']+/|[A-Z]:\\Users\\'  # proofgate-allow
KEEP='/home/(node|app|runner|deploy|user|ubuntu|vscode|www-data)/'          # proofgate-allow
tab="$(printf '\t')"; n=0
while IFS="$tab" read -r file content; do
  printf '%s' "$content" | grep -Eq "$PAT" || continue
  printf '%s' "$content" | grep -Eq "$KEEP" && continue          # container-idiom path — legitimate
  pg_ignored "$(pg_fingerprint machine-paths "$file" "$content")" && continue
  n=$((n + 1))
done < <(pg_added_with_file ':(exclude)*.md' ':(exclude)*Dockerfile*' ':(exclude)*.github/*' ':(exclude)*.gitlab-ci*')
if [ "$n" -gt 0 ]; then
  echo "⚠️  machine-paths: $n added line(s) hard-code a local machine path (/home/<you>, /Users/<you>, C:\\Users\\). It works on one box only — use a relative path or an env var."
  exit 2
fi
echo "✅ machine-paths: no local machine paths hard-coded"
exit 0
