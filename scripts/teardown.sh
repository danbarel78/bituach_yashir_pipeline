#!/usr/bin/env bash
# scripts/teardown.sh - remove everything this POC installed.
#
# Deliberately refuses to run without --yes: this deletes namespaces and
# therefore every workload in them. Argo CD-managed applications die with their
# namespaces, so the CRDs and the platform charts go too.
#
# Usage:
#   ./scripts/teardown.sh --yes            # platform + app namespaces
#   ./scripts/teardown.sh --yes --keep-data  # keep app namespaces (GitOps content)

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONFIRMED=0
KEEP_DATA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)   CONFIRMED=1; shift ;;
    --keep-data) KEEP_DATA=1; shift ;;
    -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "$CONFIRMED" -eq 1 ] || die "refusing to destroy resources without --yes (try --help)"
require_cmd kubectl helm
require_cluster

ESO_NS="external-secrets"
VAULT_NS="vault"
ARGOCD_NS="argocd"
INGRESS_NS="ingress-nginx"

uninstall() {
  local release="$1" ns="$2"
  if helm -n "$ns" status "$release" >/dev/null 2>&1; then
    log "uninstalling ${release} from ${ns}"
    helm -n "$ns" uninstall "$release" >/dev/null
    ok "${release} removed"
  else
    warn "${release} not installed in ${ns} - skipped"
  fi
}

uninstall external-secrets "$ESO_NS"
uninstall vault "$VAULT_NS"
uninstall argocd "$ARGOCD_NS"
uninstall ingress-nginx "$INGRESS_NS"

for ns in "$ESO_NS" "$VAULT_NS" "$ARGOCD_NS" "$INGRESS_NS"; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    log "deleting namespace ${ns}"
    kubectl delete namespace "$ns" --wait=false >/dev/null
    ok "${ns} scheduled for deletion"
  fi
done

# External Secrets leaves cluster-scoped CRDs behind, which would block or
# confuse a later reinstall of a different chart version.
for crd in $(kubectl get crd -o name 2>/dev/null | grep 'external-secrets.io' || true); do
  kubectl delete "$crd" --ignore-not-found >/dev/null
done
ok "external-secrets CRDs removed"

if [ "$KEEP_DATA" -eq 0 ]; then
  for ns in bituach-dev bituach-staging bituach-prod; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      log "deleting namespace ${ns}"
      kubectl delete namespace "$ns" --wait=false >/dev/null
      ok "${ns} scheduled for deletion"
    fi
  done
else
  warn "--keep-data: application namespaces left untouched"
fi

log "teardown complete (metrics-server is left in kube-system; remove it with:"
printf '       helm -n kube-system uninstall metrics-server\n'
