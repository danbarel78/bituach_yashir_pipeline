#!/usr/bin/env bash
# scripts/load-images.sh - push locally built images into the cluster's
# containerd without going through a registry.
#
# Why this exists: Docker Desktop's in-cluster runtime may fail to resolve
# ghcr.io, and a `docker build` alone does not make an image visible to the
# kubelet (they are different image stores). `ctr images import` is the
# documented fallback in handoff.md §16.
#
# Usage:
#   ./scripts/load-images.sh                       # all three services, tag :local
#   ./scripts/load-images.sh --tag 1.0.0           # a specific tag
#   ./scripts/load-images.sh engine                # just one service
#
# Prerequisite: Docker Desktop must have WSL integration enabled for this
# distro (Settings -> Resources -> WSL Integration). Without it the Windows
# docker CLI is visible through interop but refuses to talk to the daemon, and
# this script stops with a clear message instead of a confusing build error.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

REGISTRY="ghcr.io/danbarel78"
TAG="local"
SERVICES=(engine data ingest)

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:?--tag needs a value}"; shift 2 ;;
    engine|data|ingest) SERVICES=("$1"); shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_cmd docker
require_cluster

# `command -v docker` can succeed via Windows interop while still being unable
# to reach the Docker socket - check the daemon, not just the binary.
docker info >/dev/null 2>&1 \
  || die "the docker CLI cannot reach the daemon from this shell - enable Docker Desktop > Settings > Resources > WSL Integration for this distro"

# The node runs inside a Docker container; that container is the only place
# where importing an image makes it visible to the kubelet.
node_container="$(docker ps --filter 'label=io.x-k8s.kind.cluster' --format '{{.Names}}' | head -1)"
[ -n "$node_container" ] || die "could not find the cluster node container - is Kubernetes enabled in Docker Desktop?"
ok "node container: ${node_container}"

for svc in "${SERVICES[@]}"; do
  image="${REGISTRY}/bituach-yashir-${svc}:${TAG}"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    die "image not found locally: ${image} (build it first: make docker-build)"
  fi
  log "importing ${image} into the node containerd"
  docker save "$image" | docker exec -i "$node_container" \
    ctr -n k8s.io images import --digests --snapshotter overlayfs - >/dev/null 2>&1 \
    || docker save "$image" | docker exec -i "$node_container" ctr -n k8s.io images import - >/dev/null
  ok "${svc} imported"
done

log "done - reference the images as PullPolicy: IfNotPresent with the same tag"
