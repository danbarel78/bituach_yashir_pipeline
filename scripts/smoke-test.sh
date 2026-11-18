#!/usr/bin/env bash
# scripts/smoke-test.sh - post-deploy verification through the real external
# path (ingress -> Service -> pod), not through a port-forward.
#
# This is the gate the Jenkins pipeline runs after Argo CD syncs an environment
# (handoff.md §10, "Verify" stage).
#
# Usage:
#   ./scripts/smoke-test.sh --env dev
#   ./scripts/smoke-test.sh --env prod --host bituach.localhost

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENV_NAME="dev"
HOST=""
SERVICES=(engine data ingest)

while [ $# -gt 0 ]; do
  case "$1" in
    --env)  ENV_NAME="${2:?--env needs a value}"; shift 2 ;;
    --host) HOST="${2:?--host needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$ENV_NAME" in
  dev)     HOST="${HOST:-dev.bituach.localhost}" ;;
  staging) HOST="${HOST:-staging.bituach.localhost}" ;;
  prod)    HOST="${HOST:-bituach.localhost}" ;;
  *) die "--env must be dev, staging or prod (got: ${ENV_NAME})" ;;
esac

require_cmd curl

failures=0
total=0

# fetch <path> - GET through the ingress, DNS pinned to the local controller.
fetch() {
  curl -sk --max-time 10 --resolve "${HOST}:443:127.0.0.1" "https://${HOST}$1"
}

check() {
  local name="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    printf '%b  PASS%b  %s\n' "$C_GREEN" "$C_RESET" "$name"
  else
    printf '%b  FAIL%b  %s\n' "$C_RED" "$C_RESET" "$name"
    failures=$((failures + 1))
  fi
}

printf '%bSmoke test: %s (https://%s)%b\n\n' "$C_BOLD" "$ENV_NAME" "$HOST" "$C_RESET"

for svc in "${SERVICES[@]}"; do
  # The root endpoint proves routing reached the right pod.
  response="$(fetch "/${svc}/" 2>/dev/null || true)"
  if printf '%s' "$response" | grep -q "\"${svc}\""; then
    total=$((total + 1)); printf '%b  PASS%b  %-16s /\n' "$C_GREEN" "$C_RESET" "$svc"
  else
    total=$((total + 1)); printf '%b  FAIL%b  %-16s / (got: %s)\n' "$C_RED" "$C_RESET" "$svc" "${response:-<empty>}"
    failures=$((failures + 1))
  fi

  health="$(fetch "/${svc}/healthz" 2>/dev/null || true)"
  if printf '%s' "$health" | grep -q '"status"'; then
    total=$((total + 1)); printf '%b  PASS%b  %-16s /healthz\n' "$C_GREEN" "$C_RESET" "$svc"
  else
    total=$((total + 1)); printf '%b  FAIL%b  %-16s /healthz\n' "$C_RED" "$C_RESET" "$svc"
    failures=$((failures + 1))
  fi

  # /version is the evidence that the immutable tag reached the pod.
  version="$(fetch "/${svc}/version" 2>/dev/null || true)"
  if printf '%s' "$version" | grep -q '"version"'; then
    total=$((total + 1)); printf '%b  PASS%b  %-16s /version %s\n' "$C_GREEN" "$C_RESET" "$svc" \
      "$(printf '%s' "$version" | sed -n 's/.*"version":"\([^"]*\)".*/(\1)/p')"
  else
    total=$((total + 1)); printf '%b  FAIL%b  %-16s /version\n' "$C_RED" "$C_RESET" "$svc"
    failures=$((failures + 1))
  fi
done

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf '%bAll %d smoke checks passed.%b\n' "$C_GREEN" "$total" "$C_RESET"
  exit 0
fi
printf '%b%d of %d smoke checks failed.%b\n' "$C_RED" "$failures" "$total" "$C_RESET"
exit 1
