#!/usr/bin/env bash
# Shared helpers for the scripts/ directory. Source this, do not execute it.
#
# Kept dependency-free on purpose: bash + kubectl + helm only, so a reviewer can
# run the whole flow on any Linux shell without installing anything else.

set -euo pipefail

# Repository root, resolved from this file's location (scripts/lib/common.sh).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ~/.local/bin first: kubectl/helm are installed there without sudo.
export PATH="$HOME/.local/bin:$PATH"

if [ -t 1 ]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
else
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

log()  { printf '%b==>%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%b  ok%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b  !!%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%b fail%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
  done
}

# Fail early with a readable message instead of a wall of kubectl errors.
require_cluster() {
  kubectl cluster-info >/dev/null 2>&1 \
    || die "cannot reach the cluster - is Docker Desktop running with Kubernetes enabled?"
  local ctx
  ctx="$(kubectl config current-context)"
  ok "cluster reachable (context: ${ctx})"
}

# wait_for <description> <timeout-seconds> <command...>
# Polls once per second. Used where `helm --wait` is too coarse.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    if [ "$waited" -ge "$timeout" ]; then
      warn "timed out after ${timeout}s waiting for: ${desc}"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  ok "ready: ${desc} (${waited}s)"
}

# rollout_ok <namespace> <deployment-name>
rollout_ok() {
  kubectl -n "$1" rollout status "deployment/$2" --timeout=5s >/dev/null 2>&1
}
