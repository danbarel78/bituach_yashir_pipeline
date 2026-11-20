#!/usr/bin/env bash
# scripts/verify.sh - Phase 2 checkpoint report.
#
# Answers one question: is the platform layer actually working, not just
# installed? Every line is a real check against the live cluster.
#
# Exit code 0 = all checks pass; 1 = at least one failure.
#
# Usage: ./scripts/verify.sh

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd kubectl helm curl

ARGOCD_NS="argocd"
VAULT_NS="vault"
ESO_NS="external-secrets"
INGRESS_NS="ingress-nginx"

failures=0
total=0

report() {
  local status="$1" name="$2" detail="${3:-}"
  total=$((total + 1))
  if [ "$status" = "ok" ]; then
    printf '%b  PASS%b  %-46s %s\n' "$C_GREEN" "$C_RESET" "$name" "$detail"
  else
    printf '%b  FAIL%b  %-46s %s\n' "$C_RED" "$C_RESET" "$name" "$detail"
    failures=$((failures + 1))
  fi
}

# check <name> <command...> - records PASS/FAIL from the command's exit status.
check() {
  local name="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    report ok "$name"
  else
    report fail "$name" "$(printf '%s' "$out" | tail -1 | cut -c1-90)"
  fi
}

# http_ok <host> [path] - exercise the ingress with TLS verification off
# (self-signed by design) and DNS bypassed via --resolve.
http_ok() {
  local host="$1" path="${2:-/}"
  local code
  code="$(curl -sk --max-time 10 -o /dev/null -w '%{http_code}' \
    --resolve "${host}:443:127.0.0.1" "https://${host}${path}" || true)"
  [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "307" ]
}

# http_responds <host> [path] - weaker than http_ok: any HTTP status proves the
# controller accepted the connection and routed it (404 means no rule matched,
# which is the expected answer when probing the bare controller).
http_responds() {
  local host="$1" path="${2:-/}"
  local code
  code="$(curl -sk --max-time 10 -o /dev/null -w '%{http_code}' \
    --resolve "${host}:443:127.0.0.1" "https://${host}${path}" || true)"
  [ "$code" != "000" ] && [ -n "$code" ]
}

# vault_field <field> - read one boolean from `vault status -format=json`,
# tolerating pretty-printed JSON (spaces after the colon).
vault_field() {
  kubectl -n "$VAULT_NS" exec vault-0 -- vault status -format=json 2>/dev/null \
    | tr -d ' \n' | grep -q "\"$1\":true"
}

printf '%b%s%b\n' "$C_BOLD" "Bituach Yashir - platform verification" "$C_RESET"
printf 'context: %s\n\n' "$(kubectl config current-context 2>/dev/null || echo '<none>')"

printf '%b-- cluster%b\n' "$C_BOLD" "$C_RESET"
check "node Ready" bash -c \
  'kubectl get nodes --no-headers | grep -q " Ready"'

printf '\n%b-- metrics-server (HPA backend)%b\n' "$C_BOLD" "$C_RESET"
check "metrics APIService available" bash -c \
  'test "$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath="{.status.conditions[?(@.type==\"Available\")].status}")" = True'
check "kubectl top nodes returns data" bash -c \
  'kubectl top nodes --no-headers | grep -q .'

printf '\n%b-- ingress-nginx%b\n' "$C_BOLD" "$C_RESET"
check "controller rollout complete" rollout_ok "$INGRESS_NS" ingress-nginx-controller
check "IngressClass nginx present" bash -c \
  'kubectl get ingressclass nginx >/dev/null 2>&1'
check "ingress controller answers on 443" http_responds localhost

printf '\n%b-- TLS%b\n' "$C_BOLD" "$C_RESET"
check "secret argocd/argocd-server-tls" kubectl -n "$ARGOCD_NS" get secret argocd-server-tls
check "secret vault/vault-tls" kubectl -n "$VAULT_NS" get secret vault-tls

printf '\n%b-- Argo CD%b\n' "$C_BOLD" "$C_RESET"
check "argocd-server rollout complete" rollout_ok "$ARGOCD_NS" argocd-server
# The application controller is a StatefulSet (not a Deployment) in Argo CD v3.
check "argocd-application-controller ready" bash -c \
  'kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5s >/dev/null 2>&1'
check "argocd-repo-server rollout complete" rollout_ok "$ARGOCD_NS" argocd-repo-server
check "https://argocd.localhost reachable" http_ok argocd.localhost

printf '\n%b-- Vault%b\n' "$C_BOLD" "$C_RESET"
check "vault-0 running" bash -c \
  'test "$(kubectl -n vault get pod vault-0 -o jsonpath="{.status.phase}")" = Running'
check "vault initialized" vault_field initialized
check "vault unsealed" bash -c \
  'kubectl -n vault exec vault-0 -- vault status -format=json 2>/dev/null | tr -d " \n" | grep -q "\"sealed\":false"'
check "https://vault.localhost reachable" http_ok vault.localhost

printf '\n%b-- External Secrets Operator%b\n' "$C_BOLD" "$C_RESET"
check "external-secrets rollout complete" rollout_ok "$ESO_NS" external-secrets
check "external-secrets-webhook rollout complete" rollout_ok "$ESO_NS" external-secrets-webhook
check "external-secrets-cert-controller rollout complete" rollout_ok "$ESO_NS" external-secrets-cert-controller
check "CRD ExternalSecret present" kubectl get crd externalsecrets.external-secrets.io
check "CRD ClusterSecretStore present" kubectl get crd clustersecretstores.external-secrets.io

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf '%bAll %d checks passed.%b\n' "$C_GREEN" "$total" "$C_RESET"
  exit 0
fi
printf '%b%d of %d checks failed.%b\n' "$C_RED" "$failures" "$total" "$C_RESET"
exit 1
