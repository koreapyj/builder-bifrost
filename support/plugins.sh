#!/usr/bin/env bash
#
# Resolve and stage the plugins listed under plugins/.
#
#   support/plugins.sh resolve <lockfile>
#       Resolve every plugin's REF to a commit and write "<name> <sha>" lines
#       to <lockfile>. Branch REFs therefore track their branch: a new plugin
#       commit changes the lock, the patch-set revision and the image tag.
#   support/plugins.sh stage <bifrost-tree> <lockfile>
#       Put each plugin's source at the locked commit into
#       <bifrost-tree>/.builder/plugins/<name>/, apply plugins/<name>/patches/
#       (fuzz=0), and write the build inputs the Dockerfile reads from
#       <bifrost-tree>/.builder/ (build.sh, <name>.conf, go-version).
#
# Local override (Makefile only): PLUGIN_SRC_<name>=<dir> (dashes in <name>
# become underscores) uses a local checkout instead of REPO@REF, e.g.
#   make prepare PLUGIN_SRC_payload=../bifrost-plugin-payload

set -euo pipefail
. "$(dirname "$0")/common.sh"

# Plugin repositories may be private and in another account.
_GH_TOKEN="${PLUGINS_GH_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"

override_dir() {
    local var="PLUGIN_SRC_${1//-/_}"
    printf '%s' "${!var:-}"
}

resolve() {
    local lock="$1" name sha out=''
    for name in $(plugin_names); do
        load_plugin_conf "${name}"
        if [ -n "$(override_dir "${name}")" ]; then
            sha=local
            REPO="$(override_dir "${name}")" REF=''
        elif [ -n "${REPO}" ]; then
            sha="$(gh_api "repos/${REPO}/commits/${REF}" | jq -r '.sha')" \
                || die "plugins/${name}: cannot resolve ${REPO}@${REF}"
            [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || die "plugins/${name}: unexpected sha '${sha}'"
        else
            sha=in-tree
        fi
        echo "plugin ${name}: ${REPO:-plugins/${name}/src}${REF:+@${REF}} -> ${sha}" >&2
        out+="${name} ${sha}"$'\n'
    done
    printf '%s' "${out}" > "${lock}"
}

copy_tree() {
    # copy_tree <from> <to>: copy a local source tree without VCS/build clutter.
    mkdir -p "$2"
    # Unanchored patterns: they match at any depth.
    tar -C "$1" --exclude=.git --exclude=node_modules --exclude=.tmp --exclude=.ref \
        --exclude=.pc --exclude='*.so' -cf - . \
        | tar -C "$2" -xf -
}

go_version_of() {
    # Highest `go` / `toolchain` version over the given go.mod files.
    awk '$1 == "go" { print $2 } $1 == "toolchain" { sub(/^go/, "", $2); print $2 }' "$@" \
        | sort -V | tail -n1
}

stage() {
    local src lock name sha dest ov
    src="$(cd "$1" && pwd)"
    lock="$2"
    [ -f "${src}/transports/go.mod" ] || die "${src} is not a Bifrost tree"
    [ -f "${lock}" ] || die "${lock} not found -- run 'support/plugins.sh resolve' first"

    local b="${src}/.builder"
    rm -rf "${b}"
    mkdir -p "${b}/plugins"
    cp "${BUILDER_ROOT}/support/build.sh" "${b}/build.sh"
    cp "${lock}" "${b}/plugins.lock"

    # Every configured plugin must be in the lock, and nothing else.
    local want have
    want="$(plugin_names)"
    have="$(awk 'NF { print $1 }' "${lock}" | LC_ALL=C sort)"
    [ "${want}" = "${have}" ] || die "${lock} does not match plugins/ (re-run resolve)"

    while read -r name sha; do
        [ -n "${name}" ] || continue
        load_plugin_conf "${name}"
        dest="${b}/plugins/${name}"
        ov="$(override_dir "${name}")"
        if [ "${sha}" = local ]; then
            [ -n "${ov}" ] && [ -d "${ov}" ] || die "plugins/${name}: lock says 'local' but PLUGIN_SRC_${name//-/_} is not a directory"
            echo "plugin ${name}: local checkout ${ov}"
            copy_tree "${ov}" "${dest}"
        elif [ "${sha}" = in-tree ]; then
            echo "plugin ${name}: plugins/${name}/src"
            copy_tree "${BUILDER_ROOT}/plugins/${name}/src" "${dest}"
        else
            echo "plugin ${name}: ${REPO}@${sha}"
            mkdir -p "${dest}"
            gh_api "repos/${REPO}/tarball/${sha}" | tar -xz --strip-components=1 -C "${dest}"
        fi
        [ -f "${dest}/go.mod" ] || die "plugins/${name}: no go.mod at the plugin root"

        bash "${BUILDER_ROOT}/support/apply-patches.sh" "${dest}" "${BUILDER_ROOT}/plugins/${name}/patches"

        {
            printf 'PACKAGE=%q\n' "${PACKAGE}"
            printf 'PREBUILD=%q\n' "${PREBUILD}"
        } > "${b}/plugins/${name}.conf"
        printf '%s\n' "${SMOKE_CONFIG}" | jq -c . > "${b}/plugins/${name}.smoke.json" \
            || die "plugins/${name}: SMOKE_CONFIG is not valid JSON"
    done < "${lock}"

    # Go toolchain for the builder stage: the highest version any workspace
    # module asks for (the same module set build.sh puts into go.work).
    local mods=("${src}/core/go.mod" "${src}/framework/go.mod" "${src}/transports/go.mod")
    local m
    for m in "${src}"/plugins/*/go.mod "${b}"/plugins/*/go.mod; do
        [ -f "${m}" ] && mods+=("${m}")
    done
    go_version_of "${mods[@]}" > "${b}/go-version"
    echo "Go toolchain: $(cat "${b}/go-version")"
}

cmd="${1:-}"
case "${cmd}" in
resolve)
    [ "$#" -eq 2 ] || { echo "usage: $0 resolve <lockfile>" >&2; exit 2; }
    resolve "$2"
    ;;
stage)
    [ "$#" -eq 3 ] || { echo "usage: $0 stage <bifrost-tree> <lockfile>" >&2; exit 2; }
    stage "$2" "$3"
    ;;
*)
    echo "usage: $0 {resolve|stage} ..." >&2
    exit 2
    ;;
esac
