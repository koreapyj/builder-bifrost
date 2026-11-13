#!/usr/bin/env bash
#
# Print the patch-set revision: the first 12 hex digits of a sha256 over
# everything that changes what gets built on top of upstream.
#
#   support/rev.sh <plugins-lockfile>
#
# Inputs: patches/ (series + *.patch), plugins/ (every file, including
# plugin.conf, patches and in-tree sources), the resolved plugin commits
# (<plugins-lockfile>), and the build scripts. README edits do not change it.

set -euo pipefail
. "$(dirname "$0")/common.sh"

[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: $0 <plugins-lockfile>" >&2; exit 2; }
lock="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

cd "${BUILDER_ROOT}"
{
    find patches plugins -type f ! -name '*.md' 2>/dev/null | LC_ALL=C sort | while read -r f; do
        printf '== %s\n' "${f}"
        cat "${f}"
    done
    printf '== plugins.lock\n'
    cat "${lock}"
    for f in support/apply-patches.sh support/plugins.sh support/build.sh \
             support/Dockerfile support/Dockerfile.dockerignore; do
        printf '== %s\n' "${f}"
        cat "${f}"
    done
} | sha256sum | cut -c1-12
