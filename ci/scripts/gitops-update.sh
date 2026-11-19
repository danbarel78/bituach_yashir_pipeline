#!/usr/bin/env bash
# ci/scripts/gitops-update.sh - write the new digests into the target overlay,
# commit them with [skip ci] and push. Called by the Jenkinsfile's GitOps stage.
#
# Required environment:
#   ENV_NAME       dev | staging | prod
#   VERSION        the computed version, e.g. 0.0.1-dev.42+abc1234
#   TARGET_BRANCH  branch to push to (develop | release/x.y.z | main)
#   DIGESTS_FILE   file with "<service> <image>@sha256:..." lines
#   REPO           owner/name on GitHub
#   GIT_TOKEN      repository write token (masked by Jenkins)
#   BUILD_NUMBER   Jenkins build number, used for the temp branch name
#
# Safety:
#   * only gitops/overlays/<env>/kustomization.yaml may change;
#   * the overlay must still render (kubectl kustomize);
#   * the commit carries [skip ci] so it cannot trigger another build;
#   * push retries with fetch+rebase on non-fast-forward, and never resolves
#     a conflict automatically.
set -euo pipefail

: "${ENV_NAME:?ENV_NAME is required}"
: "${VERSION:?VERSION is required}"
: "${TARGET_BRANCH:?TARGET_BRANCH is required}"
: "${DIGESTS_FILE:?DIGESTS_FILE is required}"
: "${REPO:?REPO is required}"
: "${GIT_TOKEN:?GIT_TOKEN is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

set +x

echo "==> pinning digests in ${ENV_NAME}"
python3 ci/scripts/pin_digests.py --env "$ENV_NAME" --digests "$DIGESTS_FILE"

echo "==> rendering the overlay"
kubectl kustomize "gitops/overlays/${ENV_NAME}" >/dev/null

git config user.name "jenkins-ci"
git config user.email "jenkins-ci@localhost"
git checkout -B "ci/gitops-${BUILD_NUMBER}"

git add "gitops/overlays/${ENV_NAME}/kustomization.yaml"

unexpected="$(git diff --cached --name-only | grep -v '^gitops/overlays/' || true)"
if [ -n "$unexpected" ]; then
  echo "refusing to commit: unexpected staged paths:" >&2
  echo "$unexpected" >&2
  exit 1
fi

if git diff --cached --quiet; then
  echo "==> overlay already pinned; nothing to commit"
  git rev-parse HEAD > gitops-revision.txt
  exit 0
fi

git commit -q -m "chore(gitops): pin ${VERSION} [skip ci]"
echo "==> committed $(git rev-parse --short HEAD)"

remote="https://x-access-token:${GIT_TOKEN}@github.com/${REPO}.git"

for attempt in 1 2 3; do
  echo "==> push attempt ${attempt} -> ${TARGET_BRANCH}"
  if git push -q "$remote" "HEAD:${TARGET_BRANCH}"; then
    echo "==> pushed to ${TARGET_BRANCH}"
    git rev-parse HEAD > gitops-revision.txt
    exit 0
  fi
  echo "==> push rejected; rebasing on origin/${TARGET_BRANCH}"
  git fetch -q "$remote" "$TARGET_BRANCH"
  git rebase FETCH_HEAD || {
    git rebase --abort || true
    echo "rebase conflict - refusing to resolve automatically" >&2
    exit 1
  }
done

echo "push failed after 3 attempts" >&2
exit 1