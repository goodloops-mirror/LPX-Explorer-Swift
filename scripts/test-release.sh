#!/bin/bash
# Exercises version.sh and release.sh in a throw-away git repository (never touches this repo).
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export LPX_RELEASE_REPO="$T" LPX_VERSION_REPO="$T"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; }
cd "$T"
git init -q -b main; git config user.email t@t; git config user.name t
printf '# Changelog\n\nIntro.\n\n## [Unreleased]\n\n- Hand-written note.\n' > CHANGELOG.md
git add .; git commit -q -m "start"; git tag -a v0.0.9 -m legacy
[ "$("$S/version.sh")" = "0.0.0" ] || fail "legacy tags must not count"; ok "legacy v0.0.x tags are ignored"

"$S/release.sh" 0.1.0 --dry-run --skip-tests >/dev/null
git rev-parse -q --verify refs/tags/v0.1.0 >/dev/null && fail "dry run created a tag"
grep -q '## \[0.1.0\]' CHANGELOG.md && fail "dry run edited the changelog"; ok "dry run changes nothing"

"$S/release.sh" 0.1.0 --skip-tests >/dev/null
[ "$("$S/version.sh")" = "0.1.0" ] || fail "version after release"
grep -q '^## \[0.1.0\] - ' CHANGELOG.md || fail "section missing"
grep -q 'Hand-written note' CHANGELOG.md || fail "manual note lost"
awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f && /Hand-written/{exit 1}' CHANGELOG.md || fail "Unreleased not emptied"
[ -z "$(git status --porcelain)" ] || fail "tree not clean after release"; ok "first release v0.1.0"

echo a > a; git add a; git commit -q -m "feat: shiny search"
echo b > b; git add b; git commit -q -m "fix: crash on empty folder"
echo c > c; git add c; git commit -q -m "Tidy the sidebar"
"$S/release.sh" minor --skip-tests >/dev/null
[ "$("$S/version.sh")" = "0.2.0" ] || fail "minor bump"
sed -n '/^## \[0.2.0\]/,/^## \[0.1.0\]/p' CHANGELOG.md > section.txt
grep -q '### Added' section.txt && grep -q -- '- shiny search' section.txt || fail "feat not grouped"
grep -q '### Fixed' section.txt && grep -q -- '- crash on empty folder' section.txt || fail "fix not grouped"
grep -q '### Changed' section.txt && grep -q -- '- Tidy the sidebar' section.txt || fail "other not grouped"
grep -q 'Release v' section.txt && fail "release commit leaked into notes"
rm section.txt; ok "commit subjects grouped"

"$S/release.sh" patch --skip-tests >/dev/null 2>&1 && fail "empty release allowed"; ok "refuses a release with nothing new"
echo d > d; git add d; git commit -q -m "fix: typo"
echo dirty >> a
"$S/release.sh" patch --skip-tests >/dev/null 2>&1 && fail "dirty tree allowed"; git checkout -q a; ok "refuses a dirty tree"
"$S/release.sh" patch --skip-tests >/dev/null
[ "$("$S/version.sh")" = "0.2.1" ] || fail "patch bump"
[ "$(git tag --list 'v0.*' | sort | tr '\n' ' ')" = "v0.0.9 v0.1.0 v0.2.0 v0.2.1 " ] || fail "tags"
[ "$(grep -c '^## \[' CHANGELOG.md)" = "4" ] || fail "changelog sections: $(grep '^## \[' CHANGELOG.md | tr '\n' ' ')"; ok "patch release, changelog stays well-formed"
git checkout -q v0.1.0
[ "$("$S/version.sh")" = "0.1.0" ] || fail "checkout of an old tag must report that tag"
[ "$("$S/version.sh" --describe)" = "v0.1.0" ] || fail "describe at a tag: $("$S/version.sh" --describe)"; git checkout -q main; ok "version follows the checked-out commit"
echo "all release tests passed"
