#!/bin/bash
# Cut a release: update CHANGELOG.md, commit it, and tag the commit. Never pushes.
#
#   scripts/release.sh <major|minor|patch|X.Y.Z> [--dry-run] [--skip-tests] [--no-package]
#
# The new CHANGELOG section = the hand-written notes under "## [Unreleased]"
# + commit subjects since the previous release, grouped (feat: → Added, fix: → Fixed, everything else → Changed).
# Conventional prefixes (feat:, fix:, docs:, perf:, refactor:, test:, chore:) are optional.
# After tagging it builds the app and zips it to dist/ (scripts/package.sh); --no-package skips that.
# --dry-run prints the section and changes nothing.
# Env: RELEASE_TRAILER="Co-Authored-By: …" is appended to the release commit message.
# Env: LPX_RELEASE_REPO=<dir> runs against another repository (used by scripts/test-release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPTS="$PWD/scripts"
[ -n "${LPX_RELEASE_REPO:-}" ] && cd "$LPX_RELEASE_REPO"

bump="${1:-}"; dry=0; skip_tests=0; package=1
shift || true
for a in "$@"; do case "$a" in --dry-run) dry=1 ;; --skip-tests) skip_tests=1 ;; --no-package) package=0 ;; *) echo "unknown option $a" >&2; exit 2 ;; esac; done
[ -n "$bump" ] || { echo "usage: scripts/release.sh <major|minor|patch|X.Y.Z> [--dry-run] [--skip-tests] [--no-package]" >&2; exit 2; }

current="$(LPX_VERSION_REPO="$PWD" "$SCRIPTS/version.sh")"
prev_tag=""; [ "$current" != "0.0.0" ] && prev_tag="v$current"
IFS=. read -r MA MI PA <<<"$current"
case "$bump" in
  major) new="$((MA + 1)).0.0" ;;
  minor) new="$MA.$((MI + 1)).0" ;;
  patch) new="$MA.$MI.$((PA + 1))" ;;
  [0-9]*.[0-9]*.[0-9]*) new="$bump" ;;
  *) echo "bad version '$bump'" >&2; exit 2 ;;
esac
tag="v$new"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "tag $tag already exists" >&2; exit 1; }
[ -f CHANGELOG.md ] || { echo "CHANGELOG.md missing" >&2; exit 1; }
if [ "$dry" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "working tree has uncommitted changes; commit or stash first" >&2; exit 1
fi

# Hand-written notes under [Unreleased].
manual="$(awk '/^## \[Unreleased\]/{f=1; next} /^## \[/{f=0} f' CHANGELOG.md | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed '/./,$!d')"

# Commit subjects since the previous release (none for the very first release of the series).
added=""; fixed=""; changed=""
if [ -n "$prev_tag" ]; then
  while IFS= read -r subject; do
    [ -z "$subject" ] && continue
    case "$subject" in "Release v"*) continue ;; esac
    case "$subject" in
      feat:*|feat\(*) added="$added- ${subject#*: }"$'\n' ;;
      fix:*|fix\(*)   fixed="$fixed- ${subject#*: }"$'\n' ;;
      docs:*|chore:*|test:*|refactor:*|perf:*) changed="$changed- ${subject#*: }"$'\n' ;;
      *) changed="$changed- $subject"$'\n' ;;
    esac
  done < <(git log --no-merges --format=%s "$prev_tag..HEAD")
fi

section="## [$new] - $(date +%Y-%m-%d)"$'\n'
[ -n "$manual" ] && section="$section"$'\n'"$manual"$'\n'
[ -n "$added" ] && section="$section"$'\n'"### Added"$'\n'"$added"
[ -n "$fixed" ] && section="$section"$'\n'"### Fixed"$'\n'"$fixed"
[ -n "$changed" ] && section="$section"$'\n'"### Changed"$'\n'"$changed"
if [ -z "$manual$added$fixed$changed" ]; then echo "nothing to release since ${prev_tag:-the start}" >&2; exit 1; fi

echo "Releasing $tag (was ${prev_tag:-none})"; echo; printf '%s\n' "$section"
[ "$dry" = 1 ] && { echo "(dry run: nothing changed)"; exit 0; }

if [ "$skip_tests" = 0 ] && [ -z "${LPX_RELEASE_REPO:-}" ]; then swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1; fi

# Rewrite CHANGELOG: empty [Unreleased] on top, the new section below it, older sections untouched.
tmp="$(mktemp)"; sec="$(mktemp)"
printf '%s\n' "$section" > "$sec"
awk -v secfile="$sec" '
  /^## \[Unreleased\]/ && !done { print; print ""; while ((getline line < secfile) > 0) print line; skip=1; done=1; next }
  /^## \[/ && skip { skip=0 }
  !skip { print }
' CHANGELOG.md > "$tmp"
# Keep a blank line before every heading.
awk 'NR>1 && /^## \[/ && prev !~ /^$/ { print "" } { print; prev=$0 }' "$tmp" > CHANGELOG.md
rm -f "$tmp" "$sec"

git add CHANGELOG.md
msg="Release $tag"; [ -n "${RELEASE_TRAILER:-}" ] && msg="$msg"$'\n\n'"$RELEASE_TRAILER"
git commit -q -m "$msg"
git tag -a "$tag" -m "LPX Explorer $new"$'\n\n'"$section"
if [ "$package" = 1 ] && [ -z "${LPX_RELEASE_REPO:-}" ]; then "$SCRIPTS/package.sh"; fi
echo "Created commit and tag $tag. Not pushed — when ready: git push origin main $tag"
