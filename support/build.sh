#!/usr/bin/env bash
#
# Compile bifrost-http and every staged plugin in ONE Go workspace.
#
#   bash .builder/build.sh <out-dir>
#
# Runs inside the builder stage of support/Dockerfile with the patched Bifrost
# tree (plus .builder/ from support/plugins.sh) as the working directory.
#
# Go plugins (-buildmode=plugin) load only into a host built from the same
# package sources, the same dependency versions, the same toolchain and the
# same build flags. Hence:
#   * one go.work holds core/, framework/, transports/ and plugins/* of the
#     patched tree (like upstream's transports/Dockerfile.local) plus every
#     plugin module, so patches to core/framework reach the host AND the
#     plugins, and dependency versions are chosen once for everything;
#   * host and plugins share ${GOBUILD} (same flags) and toolchain
#     (GOTOOLCHAIN=local: never silently download another one);
#   * cgo is on and the host is linked dynamically (the official image links
#     statically, and a static binary cannot dlopen plugins).

set -euo pipefail

out="${1:?usage: $0 <out-dir>}"
root="$(pwd)"
[ -f transports/go.mod ] && [ -d .builder ] || { echo "run from a staged Bifrost tree" >&2; exit 2; }

export GOWORK="${root}/go.work" GOTOOLCHAIN=local CGO_ENABLED=1 GOFLAGS=
GOBUILD=(go build -trimpath -buildvcs=false)

version="$(tr -d '[:space:]' < transports/version)"
echo "==> Bifrost v${version}, $(go version)"

# ---------------------------------------------------------------- workspace
rm -f go.work go.work.sum
go work init ./core ./framework ./transports
for d in ./plugins/*/ ./.builder/plugins/*/; do
    [ -f "${d}go.mod" ] && go work use "${d%/}"
done
cat go.work
# Record checksums for versions the combined module graph selects (go.work.sum).
go mod download

# ---------------------------------------------------------------- plugin pre-build hooks
plugins=()
for conf in .builder/plugins/*.conf; do
    [ -e "${conf}" ] || continue
    plugins+=("$(basename "${conf}" .conf)")
done

for name in "${plugins[@]}"; do
    (
        # shellcheck disable=SC1090
        . ".builder/plugins/${name}.conf"
        if [ -n "${PREBUILD}" ]; then
            echo "==> ${name}: pre-build: ${PREBUILD}"
            cd ".builder/plugins/${name}"
            bash -euo pipefail -c "${PREBUILD}"
        fi
    )
done

# ---------------------------------------------------------------- host
mkdir -p "${out}/plugins"
echo "==> bifrost-http"
(
    cd transports/bifrost-http
    "${GOBUILD[@]}" -ldflags "-X main.Version=v${version}" -o "${out}/main" .
)

# ---------------------------------------------------------------- plugins
for name in "${plugins[@]}"; do
    (
        # shellcheck disable=SC1090
        . ".builder/plugins/${name}.conf"
        echo "==> ${name}: go build -buildmode=plugin ${PACKAGE}"
        cd ".builder/plugins/${name}"
        "${GOBUILD[@]}" -buildmode=plugin -o "${out}/plugins/${name}.so" "${PACKAGE}"
    )
done

cp .builder/plugins.lock "${out}/plugins/plugins.lock"
ls -l "${out}" "${out}/plugins"
