#!/usr/bin/env bash
# Validate and tag an infrastructure point release from indev.
set -euo pipefail

VALID_HOSTS="@validHosts@"
JQ="@jq@/bin/jq"
RELEASE_BRANCH="indev"

usage() {
  cat <<'USAGE'
Usage: releaseInfra vMAJOR.MINOR.PATCH [--push] [--dry-run]

Creates an annotated release tag from the indev branch after validating the
flake, all exported host configurations, release notes, and automation config.

Options:
  --push     Push indev and the new tag to origin after creating the tag.
  --dry-run  Run all release checks without creating or pushing a tag.
  -h, --help Show this help text.
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

tag=""
push=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      push=true
      ;;
    --dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [[ -n "$tag" ]]; then
        fail "Only one release tag may be provided."
      fi
      tag="$1"
      ;;
  esac
  shift
done

if [[ -z "$tag" ]]; then
  usage
  exit 1
fi

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "Release tag must use SemVer form vMAJOR.MINOR.PATCH, got: $tag"
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$RELEASE_BRANCH" ]]; then
  fail "Releases must be created from $RELEASE_BRANCH; current branch is $current_branch."
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  fail "Working tree must be clean before creating a release."
fi

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
  fail "Local tag already exists: $tag"
fi

set +e
remote_tag_output="$(git ls-remote --exit-code --tags origin "refs/tags/$tag" 2>&1)"
remote_tag_status=$?
set -e

case "$remote_tag_status" in
  0)
    fail "Remote tag already exists: $tag"
    ;;
  2)
    ;;
  *)
    echo "$remote_tag_output" >&2
    fail "Could not check remote tags for $tag."
    ;;
esac

if [[ ! -f CHANGELOG.md ]]; then
  fail "CHANGELOG.md is required for releases."
fi

if ! grep -Eq "^## \\[$tag\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
  fail "CHANGELOG.md must contain a release heading like: ## [$tag] - YYYY-MM-DD"
fi

echo "Validating release $tag from $RELEASE_BRANCH..."
"$JQ" empty renovate.json
nix flake show path:. --no-write-lock-file

build_args=()
for host in $VALID_HOSTS; do
  build_args+=("path:.#nixosConfigurations.$host.config.system.build.toplevel")
done
nix build --no-write-lock-file --no-link "${build_args[@]}"

bash -n hosts/devenv/tools/update-network-firewall-rules.sh
bash -n hosts/devenv/tools/release-infra.sh

if [[ "$dry_run" == true ]]; then
  echo "Dry run complete. No tag was created."
  exit 0
fi

git tag -a "$tag" -m "Release $tag"
echo "Created annotated tag $tag."

if [[ "$push" == true ]]; then
  git push origin "$RELEASE_BRANCH"
  git push origin "refs/tags/$tag"
  echo "Pushed $RELEASE_BRANCH and $tag to origin."
else
  echo "Tag is local only. Push it with:"
  echo "  git push origin $RELEASE_BRANCH"
  echo "  git push origin refs/tags/$tag"
fi
