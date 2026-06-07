#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./release.sh [vX.Y.Z]

Creates and pushes a release tag. Pushing the tag triggers the GitHub Actions
Linux release workflow, which builds and publishes the .tar.gz package.

If no tag is provided, the script derives it from pubspec.yaml:
  version: 0.2.1+1 -> v0.2.1

The release tag must match the pubspec.yaml version without the build suffix.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  echo "+ $*"
  "$@"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  die "not inside a git repository"
cd "$repo_root"

[[ -f pubspec.yaml ]] || die "pubspec.yaml not found"
[[ -f .github/workflows/release-linux.yml ]] ||
  die ".github/workflows/release-linux.yml not found"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short
  die "working tree must be clean before creating a release"
fi

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || die "detached HEAD is not supported"

git remote get-url origin >/dev/null 2>&1 || die "origin remote is not configured"

pubspec_version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
[[ -n "$pubspec_version" ]] || die "could not read version from pubspec.yaml"

release_version="${pubspec_version%%+*}"
expected_tag="v$release_version"
tag="${1:-$expected_tag}"
[[ "$tag" == v* ]] || tag="v$tag"

[[ "$tag" =~ ^v[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z.-]+)?$ ]] ||
  die "invalid release tag: $tag"

if [[ "$tag" != "$expected_tag" ]]; then
  die "tag $tag does not match pubspec.yaml version $pubspec_version; expected $expected_tag"
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "local tag already exists: $tag"
fi

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  die "remote tag already exists: $tag"
fi

echo "Preparing release $tag from branch $branch"

run flutter analyze
run flutter test
run flutter build linux --release

run git push origin "$branch"
run git tag -a "$tag" -m "Miaosic $tag"
run git push origin "$tag"

cat <<EOF

Release tag pushed: $tag
GitHub Actions will build and publish the Linux tar.gz package:
https://github.com/YUxiangLuo/miaosic/actions/workflows/release-linux.yml
EOF
