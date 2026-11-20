#!/usr/bin/env bash
# scripts/release.sh - cut a release from main (no `gh` CLI required).
#
# Usage:  ./scripts/release.sh [major|minor|patch]
#
# What it does:
#   1. bumps base_version.json (single source of truth for the last released version);
#   2. regenerates CHANGELOG.md from Conventional Commits since the previous tag;
#   3. commits the bump and creates the annotated vX.Y.Z tag;
#   4. prints the exact git push commands (pushes stay manual by design).
set -euo pipefail

bump="${1:-patch}"
case "$bump" in
  major|minor|patch) ;;
  *) echo "usage: release.sh [major|minor|patch]" >&2; exit 1 ;;
esac

cd "$(git rev-parse --show-toplevel)"
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "main" ]; then
  echo "release.sh must run on main (current branch: $branch)" >&2
  exit 1
fi

# A release commit should contain exactly the bump and the changelog. Refuse to
# run with staged or unstaged tracked changes; untracked files are ignored.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "release.sh requires a clean working tree (tracked changes present)" >&2
  git status --short >&2
  exit 1
fi

# --- 1. bump base_version.json -------------------------------------------
tag="$(python3 - "$bump" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path("base_version.json")
data = json.loads(path.read_text(encoding="utf-8"))
bump = sys.argv[1]
if bump == "major":
    data["major"], data["minor"], data["patch"] = data["major"] + 1, 0, 0
elif bump == "minor":
    data["minor"], data["patch"] = data["minor"] + 1, 0
else:
    data["patch"] += 1
data["releasedTag"] = f"v{data['major']}.{data['minor']}.{data['patch']}"
data["releasedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(data["releasedTag"])
PY
)"

echo "==> bumped base_version.json to ${tag}"

# --- 2. regenerate CHANGELOG.md ------------------------------------------
last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
range="${last_tag:+${last_tag}..}HEAD"
today="$(date -u +%Y-%m-%d)"

tmp="$(mktemp)"
{
  printf '# Changelog\n\n'
  printf 'All notable changes to this project. Generated from Conventional Commits (Keep a Changelog format).\n'
  printf '\n## [%s] - %s\n' "$tag" "$today"
} > "$tmp"

add_section() {
  local header="$1" pattern="$2" items
  items="$(git log --pretty=%s "$range" | grep -E "$pattern" | grep -vE '^Merge ' || true)"
  if [ -n "$items" ]; then
    printf '\n### %s\n' "$header" >> "$tmp"
    while IFS= read -r line; do
      printf -- '- %s\n' "$line" >> "$tmp"
    done <<< "$items"
  fi
}

add_section "Added"   '^feat'
add_section "Fixed"   '^fix'
add_section "Changed" '^(perf|refactor)'
add_section "Chore"   '^chore'

breaking="$(git log --pretty=%B "$range" | grep -E '^BREAKING CHANGE:' || true)"
if [ -n "$breaking" ]; then
  printf '\n### Breaking Changes\n' >> "$tmp"
  while IFS= read -r line; do
    printf -- '- %s\n' "${line#BREAKING CHANGE: }" >> "$tmp"
  done <<< "$breaking"
fi

if [ -f CHANGELOG.md ]; then
  # keep previous entries: everything from the first "## [" heading onwards
  awk 'found || /^## \[/{found=1; print}' CHANGELOG.md >> "$tmp"
fi
mv "$tmp" CHANGELOG.md
echo "==> regenerated CHANGELOG.md"

# --- 3. commit and tag ----------------------------------------------------
git add base_version.json CHANGELOG.md
git commit -m "chore(release): ${tag}"
git tag -a "${tag}" -m "Release ${tag}"

# --- 4. print the exact push commands -------------------------------------
cat <<EOF

==> Release ${tag} created locally. Push manually (no \`gh\` CLI):

    git push origin main --follow-tags

    # back-merge main into develop (GitFlow step 5):
    git checkout develop && git merge main && git push origin develop && git checkout main
EOF
