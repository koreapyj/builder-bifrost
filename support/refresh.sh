#!/usr/bin/env bash
#
# Rebase a quilt series onto the tree it is applied to.
#
#   support/refresh.sh <tree> <patch-dir>
#
# Pops everything, then pushes one patch at a time with fuzz allowed and
# quilt-refreshes it, so it applies with fuzz=0 again. Stops at the first patch
# that rejects: fix it (quilt push -f, resolve the .rej hunks, quilt refresh)
# and re-run. Local-only (`make refresh`).

set -euo pipefail
. "$(dirname "$0")/common.sh"

[ "$#" -eq 2 ] && [ -d "$1" ] || { echo "usage: $0 <tree> <patch-dir>" >&2; exit 2; }
command -v quilt >/dev/null || die "quilt is required"

if ! has_series "$2"; then
    echo "$2/series is empty -- nothing to refresh."
    exit 0
fi

export QUILTRC="${BUILDER_ROOT}/.quiltrc"
QUILT_PATCHES="$(cd "$2" && pwd)"
export QUILT_PATCHES
cd "$1"

quilt pop -a >/dev/null 2>&1 || true
while :; do
    rc=0
    quilt push --fuzz=2 || rc=$?
    [ "${rc}" -eq 2 ] && break
    if [ "${rc}" -ne 0 ]; then
        echo "Patch '$(quilt next)' rejects: fix it with 'quilt push -f', resolve the .rej hunks," >&2
        echo "'quilt refresh', then re-run 'make refresh'. Environment for quilt:" >&2
        echo "  export QUILTRC=${QUILTRC} QUILT_PATCHES=${QUILT_PATCHES}; cd $(pwd)" >&2
        exit 1
    fi
    quilt refresh
done
echo "All patches in ${QUILT_PATCHES} refreshed -- review and commit."
