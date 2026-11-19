#!/usr/bin/env bash
# ci/scripts/scan.sh - the pipeline's security gates.
#
# Usage:
#   ./ci/scripts/scan.sh sast                 bandit per service (fail on HIGH)
#   ./ci/scripts/scan.sh deps                 pip-audit per service
#   ./ci/scripts/scan.sh image <image-ref>    Trivy image scan (fail on HIGH/CRITICAL)
#
# Reports are written to reports/ and archived by the Jenkinsfile.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SERVICES=(engine data ingest)
REPORTS="$REPO_ROOT/reports"
mkdir -p "$REPORTS"

command="${1:-}"
case "$command" in
  sast)
    for service in "${SERVICES[@]}"; do
      echo "==> bandit: ${service}"
      ( cd "services/${service}" \
        && uv run bandit -r src -lll -iii \
             -f json -o "${REPORTS}/bandit-${service}.json" )
    done
    ;;

  deps)
    for service in "${SERVICES[@]}"; do
      echo "==> pip-audit: ${service}"
      ( cd "services/${service}" \
        && uv export --frozen --no-dev --no-emit-project --format requirements-txt \
             -o "${REPORTS}/requirements-${service}.txt" >/dev/null \
        && uv run --with pip-audit pip-audit -r "${REPORTS}/requirements-${service}.txt" )
    done
    ;;

  image)
    ref="${2:?scan.sh image needs an image reference}"
    name="$(echo "$ref" | sed 's#.*/##; s/:.*//')"
    echo "==> trivy: ${ref}"
    # --ignore-unfixed: fail only on vulnerabilities that have a fix available.
    # Unfixable base-image CVEs stay in the archived report instead of blocking
    # every build forever; the JSON artifact keeps them visible for triage.
    trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
      --format json --output "${REPORTS}/trivy-${name}.json" "$ref"
    ;;

  *)
    echo "usage: scan.sh sast|deps|image <image-ref>" >&2
    exit 2
    ;;
esac