#!/usr/bin/env bash
# scripts/gen-self-signed-cert.sh - create the local TLS secret used by every
# Ingress in this POC.
#
# Why a script and not a committed manifest: a TLS private key in a public
# repository is a finding. The certificate is therefore generated locally at
# bootstrap time and stored only in the cluster.
#
# Production path (documented in docs/architecture.md): cert-manager with a
# Let's Encrypt ClusterIssuer and automatic renewal. Nothing below is meant to
# survive past the POC.
#
# Usage:
#   ./scripts/gen-self-signed-cert.sh --namespace argocd --namespace vault
#   ./scripts/gen-self-signed-cert.sh -n bituach-dev -n bituach-staging -n bituach-prod
#
# Namespaces that do not exist yet are skipped with a warning, so this can run
# before Terraform has created the application namespaces.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

NAMESPACES=()
SECRET_NAME=""
DAYS="${DAYS:-825}"

usage() {
  cat <<'EOF'
usage: gen-self-signed-cert.sh [--namespace NS]... [--secret-name NAME] [--days N]

  --namespace NS   Namespace to receive the TLS secret (repeatable).
  --secret-name    Secret name for every namespace. Default is chosen per
                   namespace: argocd -> argocd-server-tls, vault -> vault-tls,
                   anything else -> bituach-tls.
  --days N         Certificate validity in days (default 825).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) NAMESPACES+=("${2:?--namespace needs a value}"); shift 2 ;;
    --secret-name)  SECRET_NAME="${2:?--secret-name needs a value}"; shift 2 ;;
    --days)         DAYS="${2:?--days needs a value}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ ${#NAMESPACES[@]} -gt 0 ] || die "at least one --namespace is required (try --help)"
require_cmd openssl kubectl

# Hostnames covered by the single certificate. Keep this list aligned with the
# Ingress hosts in gitops/ and platform/values/.
SAN_DNS=(
  "localhost"
  "bituach.localhost"
  "dev.bituach.localhost"
  "staging.bituach.localhost"
  "argocd.localhost"
  "vault.localhost"
  # Per-service hostnames (gitops/overlays/*/ingress-services.yaml).
  "engine.bituach.localhost"
  "data.bituach.localhost"
  "ingest.bituach.localhost"
  "engine.dev.bituach.localhost"
  "data.dev.bituach.localhost"
  "ingest.dev.bituach.localhost"
  "engine.staging.bituach.localhost"
  "data.staging.bituach.localhost"
  "ingest.staging.bituach.localhost"
)

secret_for() {
  if [ -n "$SECRET_NAME" ]; then
    printf '%s' "$SECRET_NAME"
    return
  fi
  case "$1" in
    argocd) printf 'argocd-server-tls' ;;
    vault)  printf 'vault-tls' ;;
    *)      printf 'bituach-tls' ;;
  esac
}

log "generating a self-signed certificate valid for ${DAYS} days"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

openssl_config="$tmpdir/openssl.cnf"
{
  printf '[req]\n'
  printf 'distinguished_name = dn\n'
  printf 'x509_extensions = v3_req\n'
  printf 'prompt = no\n'
  printf '[dn]\n'
  printf 'CN = bituach.localhost\n'
  printf 'O = Bituach Yashir POC\n'
  printf '[v3_req]\n'
  printf 'basicConstraints = critical,CA:FALSE\n'
  printf 'keyUsage = critical,digitalSignature,keyEncipherment\n'
  printf 'extendedKeyUsage = serverAuth\n'
  printf 'subjectAltName = @alt\n'
  printf '[alt]\n'
  i=1
  for host in "${SAN_DNS[@]}"; do
    printf 'DNS.%d = %s\n' "$i" "$host"
    i=$((i + 1))
  done
  printf 'IP.1 = 127.0.0.1\n'
} > "$openssl_config"

openssl req -x509 -nodes -newkey rsa:2048 \
  -days "$DAYS" \
  -keyout "$tmpdir/tls.key" \
  -out "$tmpdir/tls.crt" \
  -config "$openssl_config" >/dev/null 2>&1

ok "certificate created (SANs: ${SAN_DNS[*]}, IP 127.0.0.1)"

for ns in "${NAMESPACES[@]}"; do
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    warn "namespace ${ns} does not exist yet - skipping (re-run after Terraform creates it)"
    continue
  fi
  secret="$(secret_for "$ns")"
  kubectl -n "$ns" create secret tls "$secret" \
    --cert="$tmpdir/tls.crt" \
    --key="$tmpdir/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  ok "secret ${ns}/${secret} applied"
done

log "done - browsers will still warn because the certificate is self-signed by design"
