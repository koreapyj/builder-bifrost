#!/usr/bin/env bash
#
# Download the Bifrost source tree at tag transports/<version> into <dir>.
#
#   support/fetch-bifrost.sh <vX.Y.Z> <dir>
#
# <dir> must not exist yet. The tree is a plain tarball extract (no .git),
# which is all quilt needs.

set -euo pipefail
. "$(dirname "$0")/common.sh"

[ "$#" -eq 2 ] || { echo "usage: $0 <vX.Y.Z> <dir>" >&2; exit 2; }
version="$1"
dir="$2"

[[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
    || die "'${version}' is not a Bifrost version (expected vX.Y.Z)"
[ ! -e "${dir}" ] || die "${dir} already exists"

echo "Fetching ${BIFROST_GH_REPO} transports/${version} into ${dir}/"
tmp="${dir}.tmp.$$"
rm -rf "${tmp}"
mkdir -p "${tmp}"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL --retry 3 --retry-delay 2 \
    "https://codeload.github.com/${BIFROST_GH_REPO}/tar.gz/refs/tags/transports/${version}" \
    | tar -xz --strip-components=1 -C "${tmp}"

[ -f "${tmp}/transports/go.mod" ] || die "downloaded tree has no transports/go.mod"
got="v$(tr -d '[:space:]' < "${tmp}/transports/version")"
[ "${got}" = "${version}" ] || echo "warning: transports/version says ${got}, tag is ${version}" >&2

mv "${tmp}" "${dir}"
trap - EXIT
