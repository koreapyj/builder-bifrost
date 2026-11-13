#!/usr/bin/env bash
#
# Print the newest stable Bifrost gateway version as vX.Y.Z.
#
# Bifrost is a monorepo with per-module tags (core/vX, framework/vX, ...); the
# gateway release is the transports/vX.Y.Z tag. Pre-releases are ignored.
# Used by CI (.github/workflows/build.yaml) and by the Makefile.

set -euo pipefail
. "$(dirname "$0")/common.sh"

latest="$(gh_api "repos/${BIFROST_GH_REPO}/git/matching-refs/tags/transports/v" \
    | jq -r '.[].ref' \
    | sed 's#^refs/tags/transports/##' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n1 || true)"

[ -n "${latest}" ] || die "no stable transports/vX.Y.Z tag found in ${BIFROST_GH_REPO}"
printf '%s\n' "${latest}"
