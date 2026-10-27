#!/usr/bin/env bash
# Build the bundles image (Dockerfile.bundles), push it, and print "<image>@sha256:..." for
# forms-flow-ai's forms-flow-web-root-config/mfe-bundles.ref.
#
# usage: ci/build-bundles.sh [--no-cache]
#   REGISTRY  image prefix (default: localhost:5000/formsflow; a local registry is started if needed)
#   TAG       image tag (default: the v*-ad.* tag on HEAD, else <VERSION>-dev.<short sha>)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
REGISTRY=${REGISTRY:-localhost:5000/formsflow}
log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

cache_args=()
if [ "${1:-}" = --no-cache ]; then
  cache_args=(--no-cache --build-arg "CACHE_ID=clean-$(date +%s)")
fi
SHA=$(git -C "$REPO" rev-parse HEAD)
if [ -z "${TAG:-}" ]; then
  TAG=$(git -C "$REPO" tag --points-at HEAD --list 'v*-ad.*' | sort -V | tail -1)
  [ -n "$TAG" ] || TAG="$(cat "$REPO/VERSION")-dev.$(git -C "$REPO" rev-parse --short=9 HEAD)"
fi
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] || log "warning: uncommitted changes are included in the build"

ref=$REGISTRY/forms-flow-mfe-bundles:$TAG
log "build $ref"
docker build --progress=plain -f "$REPO/Dockerfile.bundles" "${cache_args[@]}" \
  --label org.opencontainers.image.source=https://github.com/rzunigac/forms-flow-ai-micro-front-ends \
  --label org.opencontainers.image.revision="$SHA" \
  --label org.opencontainers.image.version="$TAG" \
  -t "$ref" "$REPO" >&2

if [[ $ref == localhost:5000/* ]] && ! docker inspect ffci-registry >/dev/null 2>&1; then
  log "starting local registry on localhost:5000"
  docker run -d --name ffci-registry -p 5000:5000 registry:2 >/dev/null
fi
log "push $ref"
docker push -q "$ref" >/dev/null
digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$ref" | grep "^${ref%:*}@" | head -1)
[ -n "$digest" ] || { echo "error: no digest for $ref" >&2; exit 1; }
echo "$digest"
