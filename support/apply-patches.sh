#!/usr/bin/env bash
#
# Apply a quilt series to a source tree with zero fuzz.
#
#   support/apply-patches.sh <tree> <patch-dir>
#
# Used for the Bifrost tree (patch-dir patches/) and for each plugin that has
# plugins/<name>/patches/. A patch that needs fuzz or rejects fails, so drift
# against a new upstream release surfaces as a failed run instead of a silently
# mis-applied patch. A missing or empty series is a no-op.

set -euo pipefail
. "$(dirname "$0")/common.sh"

[ "$#" -eq 2 ] && [ -d "$1" ] || { echo "usage: $0 <tree> <patch-dir>" >&2; exit 2; }
tree="$(cd "$1" && pwd)"
patches="$(cd "$2" 2>/dev/null && pwd || true)"

if [ -z "${patches}" ] || ! has_series "${patches}"; then
    echo "${2}/series is empty -- nothing to apply to ${1}."
    exit 0
fi

command -v quilt >/dev/null || die "quilt is required to apply ${2}/series"

export QUILTRC="${BUILDER_ROOT}/.quiltrc"
export QUILT_PATCHES="${patches}"

rc=0
(cd "${tree}" && quilt push -a --fuzz=0) || rc=$?
# quilt exits 2 when there is nothing left to push (everything already applied).
if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 2 ]; then
    echo "error: ${2}/series failed to apply cleanly (fuzz=0) -- see 'make refresh' in README.md." >&2
    exit "${rc}"
fi
(cd "${tree}" && quilt applied)
