#!/usr/bin/env bash
# Guard: a version was bumped in a manifest, but nothing in the delivery cuts a release.
#
# The scar (2026-07-30). A version went to 2.2.0 in the plugin manifests, the CHANGELOG
# gained its section, the PR merged green, and the delivery was reported as "merged,
# public". The owner opened the repository and saw **2.0.0**. Both statements were true
# and only one mattered: the code was on the default branch, and no tag or release had
# ever been cut for 2.1.0 or 2.2.0. A version bump is invisible to everyone who is not
# reading the diff — the release IS the shop window.
#
# The general failure, which is why this is a guard and not a note: "merged" and
# "released" are different events, and a manifest bump looks exactly like the second
# while being only the first. It is the same shape as "the deploy is READY" or "the OTA
# was built" — a step that FEELS terminal and is not.
#
# WARN, never FAIL: plenty of healthy workflows bump the version in one commit and tag
# in a later one, and release automation (release-please, changesets, semantic-release,
# a tag-triggered workflow) legitimately does the cutting elsewhere. So this asks the
# question and names what to check; it does not block. It also stays quiet when the diff
# shows the release being handled — a tag-triggered workflow, a release job, or a
# release-automation config.
set -uo pipefail
# shellcheck source=/dev/null
. "${PROOFGATE_LIB:-$(dirname "$0")/../lib.sh}" 2>/dev/null || true
BASE="${PROOFGATE_BASE:?}"

CHANGED="$(git diff --name-only "$BASE"..HEAD | grep -Ev '(guards\.d/|^\.proofgate/)' || true)"
[ -n "$CHANGED" ] || { echo "✅ version-release: nothing in the diff"; exit 0; }

# Manifests whose "version" is the number a user reads.
#
# LOCAL ADAPTATION - belongs upstream in ChrnX0/proofgate. debian/control is the
# manifest of every .deb ever built, and it was not on this list, so this guard
# has been printing "no version manifest in the diff" on every single Tandem
# release. That is precisely the scar written at the top of this file: a version
# bumped, invisible to everyone not reading the diff, with no tag cut. The guard
# existed and could not see the case it was written for.
MANIFESTS='(^|/)(package\.json|plugin\.json|marketplace\.json|Cargo\.toml|pyproject\.toml|composer\.json|\.csproj|gemspec|build\.gradle(\.kts)?|pubspec\.yaml|app\.json|debian/control)$'
TOCADOS="$(printf '%s\n' "$CHANGED" | grep -E "$MANIFESTS" || true)"
[ -n "$TOCADOS" ] || { echo "✅ version-release: no version manifest in the diff"; exit 0; }

# A version line ADDED. Covers "version": "1.2.3" (JSON) and version = "1.2.3" (TOML).
SUBIU=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # -i, because Debian's field is "Version:" with a capital V and the rest of
  # the world writes it lowercase. Without it this guard found the manifest,
  # read the added line, and still reported "no version number raised" - which
  # is a worse failure than not looking at all, because it looks like a check.
  if git diff -U0 "$BASE"..HEAD -- "$f" 2>/dev/null \
      | grep -E '^\+' \
      | grep -Eqi '"?version"?[[:space:]]*[:=][[:space:]]*"?[0-9]+\.[0-9]+'; then
    SUBIU="$SUBIU $f"
  fi
done <<EOF
$TOCADOS
EOF
[ -n "$SUBIU" ] || { echo "✅ version-release: no version number raised in the diff"; exit 0; }

# Does the delivery itself handle the release? Then there is nothing to ask.
# (a) a workflow/pipeline that triggers on tags or has a release job;
# (b) release-automation config; (c) a CHANGELOG-only repo convention is NOT enough —
# a changelog entry is documentation, not publication, which is exactly the confusion.
if printf '%s\n' "$CHANGED" | grep -Eq '(release-please|changesets?/|\.changeset/|semantic-release|goreleaser)'; then
  echo "✅ version-release: release automation is part of this delivery"
  exit 0
fi
if printf '%s\n' "$CHANGED" | grep -Eq '(\.github/workflows/|\.gitlab-ci|Jenkinsfile|azure-pipelines)' \
   && git diff "$BASE"..HEAD -- '*.yml' '*.yaml' Jenkinsfile 2>/dev/null \
      | grep -E '^\+' | grep -Eqi '(tags:|refs/tags|create.?release|softprops/action-gh-release|gh release)'; then
  echo "✅ version-release: this delivery wires the release step"
  exit 0
fi

echo "⚠️  version bumped, no release in sight:$SUBIU"
echo "    A manifest bump is not a release — nobody outside the diff can see it. Before"
echo "    calling this shipped, check the tag and the release entry EXIST for the new"
echo "    version (\`git ls-remote --tags\`, the repo's releases page). If cutting it is"
echo "    someone else's step, say the delivery is PENDING that step — not published."
exit 2
