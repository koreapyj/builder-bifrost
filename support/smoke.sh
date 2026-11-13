#!/usr/bin/env bash
#
# Boot an image with every bundled plugin enabled and check that it serves.
#
#   support/smoke.sh <image>          # smoke test, then tear down
#   support/smoke.sh --run <image>    # same config, foreground (Ctrl-C to stop)
#
# The config enables each /app/plugins/<name>.so with SMOKE_CONFIG from
# plugins/<name>/plugin.conf. The smoke test passes when /health answers and
# GET /api/plugins reports every plugin as "active" -- which proves the .so
# was loaded by this bifrost-http (a toolchain/dependency mismatch fails here)
# and that the plugin's Init accepted its config.
#
# Environment: BIFROST_PORT (default 8080), SMOKE_TIMEOUT (seconds, default 120).
# Used by CI after every build and by `make smoke` / `make run`.

set -euo pipefail
. "$(dirname "$0")/common.sh"

mode=smoke
if [ "${1:-}" = "--run" ]; then
    mode=run
    shift
fi
[ "$#" -eq 1 ] || { echo "usage: $0 [--run] <image>" >&2; exit 2; }
image="$1"
port="${BIFROST_PORT:-8080}"
timeout="${SMOKE_TIMEOUT:-120}"
id="bifrost-smoke-$$"
# Bifrost >= v2.5 locks /api until dashboard auth is set up unless the request
# carries the setup token; older versions ignore both the variable and header.
setup_token="smoke-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

# ---------------------------------------------------------------- config.json
mapfile -t names < <(docker run --rm --entrypoint sh "${image}" -c \
    'cd /app/plugins && for f in *.so; do [ -e "$f" ] && echo "${f%.so}"; done; true')

plugins='[]'
for name in "${names[@]}"; do
    if [ -f "${BUILDER_ROOT}/plugins/${name}/plugin.conf" ]; then
        load_plugin_conf "${name}"
    else
        echo "warning: no plugins/${name}/plugin.conf; enabling ${name} with {}" >&2
        SMOKE_CONFIG='{}'
    fi
    plugins="$(jq -c --arg n "${name}" --argjson c "${SMOKE_CONFIG}" \
        '. + [{enabled: true, name: $n, path: "/app/plugins/\($n).so", config: $c}]' <<<"${plugins}")"
done
echo "Plugins in ${image}: ${names[*]:-(none)}"

cfgdir="$(mktemp -d)"
jq -n --argjson plugins "${plugins}" '{plugins: $plugins}' > "${cfgdir}/config.json"
chmod 0755 "${cfgdir}"
chmod 0644 "${cfgdir}/config.json"

# A named volume starts as a copy of the image's /app/data (owned by UID 1000),
# so the gateway can write its databases and logs next to config.json.
docker volume create "${id}" >/dev/null
docker run --rm -v "${id}:/app/data" -v "${cfgdir}:/cfg:ro" --entrypoint cp "${image}" \
    /cfg/config.json /app/data/config.json

ok=0
cleanup() {
    if [ "${mode}" = smoke ] && [ "${ok}" -ne 1 ]; then
        echo "---- container logs ----" >&2
        docker logs "${id}" >&2 2>&1 || true
    fi
    docker rm -f "${id}" >/dev/null 2>&1 || true
    docker volume rm -f "${id}" >/dev/null 2>&1 || true
    rm -rf "${cfgdir}"
}
trap cleanup EXIT

if [ "${mode}" = run ]; then
    echo "Bifrost on http://localhost:${port} (Ctrl-C to stop)"
    echo "Setup token for /api and the dashboard: ${setup_token}"
    docker run --rm --name "${id}" -e "BIFROST_SETUP_TOKEN=${setup_token}" -p "127.0.0.1:${port}:8080" -v "${id}:/app/data" "${image}"
    exit 0
fi

docker run -d --name "${id}" -e "BIFROST_SETUP_TOKEN=${setup_token}" -p "127.0.0.1:${port}:8080" -v "${id}:/app/data" "${image}" >/dev/null

base="http://127.0.0.1:${port}"
deadline=$(( $(date +%s) + timeout ))
running() { [ "$(docker inspect -f '{{.State.Running}}' "${id}" 2>/dev/null)" = true ]; }

echo "Waiting up to ${timeout}s for ${base}/health ..."
until curl -fsS -o /dev/null "${base}/health" 2>/dev/null; do
    running || die "container exited during startup"
    [ "$(date +%s)" -lt "${deadline}" ] || die "/health did not become ready within ${timeout}s"
    sleep 2
done
echo "/health OK"

# Plugin statuses: config-store mode answers with .name; without a config
# store .actualName carries the configured name. Match either.
for name in "${names[@]}"; do
    status=''
    while :; do
        status="$(curl -fsS -H "X-Bifrost-Setup-Token: ${setup_token}" "${base}/api/plugins" 2>/dev/null | jq -r --arg n "${name}" \
            '[.plugins[]? | select(.name == $n or .actualName == $n) | .status.status] | first // empty' || true)"
        [ "${status}" = active ] && break
        running || die "container exited while loading plugins"
        if [ "${status}" = error ] || [ "$(date +%s)" -ge "${deadline}" ]; then
            curl -sS -H "X-Bifrost-Setup-Token: ${setup_token}" "${base}/api/plugins" >&2 || true
            die "plugin ${name} is not active (status: ${status:-unknown})"
        fi
        sleep 2
    done
    echo "plugin ${name}: active"
done

ok=1
echo "Smoke test passed for ${image}"
