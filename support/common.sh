# Shared helpers for the support/ scripts. Source it; do not execute it.
#
# Environment:
#   BIFROST_GH_REPO   upstream repository (default: maximhq/bifrost)
#   GH_TOKEN          token for api.github.com (optional; avoids rate limits)
#   PLUGINS_GH_TOKEN  token for plugin repositories (default: GH_TOKEN); needed
#                     for private plugin repositories in other accounts

BIFROST_GH_REPO="${BIFROST_GH_REPO:-maximhq/bifrost}"

# Repository root (the directory that holds support/).
BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    echo "error: $*" >&2
    exit 1
}

# gh_api <path> [curl args...]: GET https://api.github.com/<path> to stdout.
# Uses $_GH_TOKEN (set by the caller) or $GH_TOKEN when present.
gh_api() {
    local path="$1"; shift
    local token="${_GH_TOKEN-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
    local auth=()
    [ -n "${token}" ] && auth=(-H "Authorization: Bearer ${token}")
    curl -fsSL --retry 3 --retry-delay 2 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "${auth[@]}" "$@" "https://api.github.com/${path}"
}

# Plugin names double as file names, Go plugin file names and env var suffixes.
valid_plugin_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

# plugin_names: the plugin directories under plugins/ that have a plugin.conf.
plugin_names() {
    local d
    for d in "${BUILDER_ROOT}"/plugins/*/; do
        [ -f "${d}plugin.conf" ] || continue
        basename "${d}"
    done | LC_ALL=C sort
}

# load_plugin_conf <name>: source plugins/<name>/plugin.conf into REPO, REF,
# PACKAGE, PREBUILD, SMOKE_CONFIG (with defaults).
load_plugin_conf() {
    local name="$1"
    valid_plugin_name "${name}" || die "invalid plugin name '${name}' (use [a-z0-9_-])"
    REPO='' REF='' PACKAGE='.' PREBUILD='' SMOKE_CONFIG='{}'
    # shellcheck disable=SC1090
    . "${BUILDER_ROOT}/plugins/${name}/plugin.conf"
    if [ -z "${REPO}" ] && [ ! -d "${BUILDER_ROOT}/plugins/${name}/src" ]; then
        die "plugins/${name}: set REPO in plugin.conf or provide plugins/${name}/src/"
    fi
    if [ -n "${REPO}" ] && [ -z "${REF}" ]; then
        die "plugins/${name}: REF is required with REPO"
    fi
}

# has_series <patch-dir>: true when <patch-dir>/series lists at least one patch.
has_series() {
    grep -qvE '^[[:space:]]*(#|$)' "$1/series" 2>/dev/null
}
