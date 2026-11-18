#!/usr/bin/env bash
# scripts/bootstrap.sh - install the platform layer on a local cluster.
#
# Idempotent: every step is `helm upgrade --install`, so running it twice is
# safe and it doubles as the "repair/resync" path. Application deployments are
# NOT installed here - they arrive through Argo CD from the GitOps overlays.
#
# What it installs, in dependency order:
#   1. metrics-server        (backs HPA; Docker Desktop does not ship it)
#   2. ingress-nginx         (single external entry point, TLS termination)
#   3. namespaces            (platform only; app namespaces belong to Terraform)
#   4. TLS secrets           (self-signed, generated locally, never committed)
#   5. Argo CD               (GitOps reconciler, https://argocd.localhost)
#   6. Vault                 (dev mode, in-memory, https://vault.localhost)
#   7. External Secrets      (runtime secret sync; store/objects land in Phase 5)
#
# Usage: ./scripts/bootstrap.sh
# Chart versions are pinned below; override any of them with the matching
# environment variable (e.g. ARGOCD_CHART=10.19.0 ./scripts/bootstrap.sh).

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# --- pinned chart versions -------------------------------------------------
METRICS_SERVER_CHART="${METRICS_SERVER_CHART:-3.14.0}"
INGRESS_NGINX_CHART="${INGRESS_NGINX_CHART:-4.15.1}"
ARGOCD_CHART="${ARGOCD_CHART:-10.18.0}"
VAULT_CHART="${VAULT_CHART:-0.34.1}"
EXTERNAL_SECRETS_CHART="${EXTERNAL_SECRETS_CHART:-2.15.0}"

# --- namespaces ------------------------------------------------------------
ARGOCD_NS="argocd"
VAULT_NS="vault"
ESO_NS="external-secrets"
INGRESS_NS="ingress-nginx"

BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-10m}"

require_cmd kubectl helm openssl
require_cluster

# --- 1. helm repositories --------------------------------------------------
log "adding helm repositories"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null
ok "repositories up to date"

# --- 2. metrics-server -----------------------------------------------------
log "installing metrics-server ${METRICS_SERVER_CHART} (HPA depends on it)"
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --version "$METRICS_SERVER_CHART" \
  --values "$REPO_ROOT/platform/values/metrics-server.yaml" \
  --wait --timeout "$BOOTSTRAP_TIMEOUT"
wait_for "metrics API v1beta1.metrics.k8s.io available" 120 \
  kubectl get apiservice v1beta1.metrics.k8s.io -o 'jsonpath={.status.conditions[?(@.type=="Available")].status}' \
  2>/dev/null || true

# --- 3. ingress-nginx ------------------------------------------------------
log "installing ingress-nginx ${INGRESS_NGINX_CHART}"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace "$INGRESS_NS" --create-namespace \
  --version "$INGRESS_NGINX_CHART" \
  --values "$REPO_ROOT/platform/values/ingress-nginx.yaml" \
  --wait --timeout "$BOOTSTRAP_TIMEOUT"

# --- 4. namespaces ---------------------------------------------------------
# Created explicitly before the TLS step: the certificate script skips
# namespaces that do not exist, and the Argo CD/Vault ingresses reference those
# secrets. Application namespaces (bituach-*) belong to Terraform (Phase 3), so
# only the platform namespaces are created here.
log "creating platform namespaces"
for ns in "$INGRESS_NS" "$ARGOCD_NS" "$VAULT_NS" "$ESO_NS"; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns" >/dev/null
done
ok "namespaces: ${INGRESS_NS}, ${ARGOCD_NS}, ${VAULT_NS}, ${ESO_NS}"

# --- 5. TLS secrets --------------------------------------------------------
# Generated here, never committed: a private key in git would be a finding.
log "generating the self-signed TLS certificate"
"$REPO_ROOT/scripts/gen-self-signed-cert.sh" \
  --namespace "$ARGOCD_NS" --namespace "$VAULT_NS"

# --- 6. Argo CD ------------------------------------------------------------
log "installing Argo CD ${ARGOCD_CHART} (https://argocd.localhost)"
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NS" --create-namespace \
  --version "$ARGOCD_CHART" \
  --values "$REPO_ROOT/platform/values/argocd.yaml" \
  --wait --timeout "$BOOTSTRAP_TIMEOUT"

# --- 7. Vault --------------------------------------------------------------
log "installing Vault ${VAULT_CHART} in dev mode (https://vault.localhost)"
helm upgrade --install vault hashicorp/vault \
  --namespace "$VAULT_NS" --create-namespace \
  --version "$VAULT_CHART" \
  --values "$REPO_ROOT/platform/values/vault.yaml" \
  --wait --timeout "$BOOTSTRAP_TIMEOUT"

# --- 8. External Secrets ---------------------------------------------------
log "installing External Secrets Operator ${EXTERNAL_SECRETS_CHART}"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "$ESO_NS" --create-namespace \
  --version "$EXTERNAL_SECRETS_CHART" \
  --values "$REPO_ROOT/platform/values/external-secrets.yaml" \
  --wait --timeout "$BOOTSTRAP_TIMEOUT"

log "bootstrap complete - run ./scripts/verify.sh for the checkpoint report"
