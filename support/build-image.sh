#!/usr/bin/env bash
#
# Build the image from a prepared tree (patches applied, plugins staged).
#
#   support/build-image.sh <bifrost-tree> <tag> [docker build args...]
#
# Used by CI and by `make build`.

set -euo pipefail
. "$(dirname "$0")/common.sh"

[ "$#" -ge 2 ] || { echo "usage: $0 <bifrost-tree> <tag> [docker build args...]" >&2; exit 2; }
src="$1"; tag="$2"; shift 2

[ -f "${src}/.builder/go-version" ] || die "${src} is not prepared -- run 'make prepare' first"
go_version="$(cat "${src}/.builder/go-version")"

echo "Building ${tag} (Go ${go_version})"
DOCKER_BUILDKIT=1 docker build \
    -f "${BUILDER_ROOT}/support/Dockerfile" \
    --build-arg "GO_VERSION=${go_version}" \
    --tag "${tag}" \
    "$@" \
    "${src}"
