# builder-bifrost

Builds a container image of [Bifrost](https://github.com/maximhq/bifrost) (the HTTP gateway,
`bifrost-http`) with our patches applied on top of the newest stable upstream release and
our Go plugins compiled into the same build, and publishes it to `ghcr.io/koreapyj/bifrost`.

The image keeps the layout of upstream's `transports/Dockerfile` (`/app/main`, the same
`docker-entrypoint.sh`, `APP_DIR=/app/data`, UID `1000:0`, port 8080), so it is a drop-in
replacement for `maximhq/bifrost`, including with the official Helm chart. Plugins are at
`/app/plugins/<name>.so`.

## Why a builder

Go plugins load only into a host built from the same package sources, the same dependency
versions and the same toolchain, and the official Bifrost binaries are statically linked and
cannot load plugins at all. So the host and the plugins are always built together here:

- [`support/build.sh`](support/build.sh) creates one `go.work` with `core/`, `framework/`,
  `transports/` and `plugins/*` of the patched Bifrost tree (as upstream's
  `transports/Dockerfile.local` does) plus every plugin module, then builds a dynamically
  linked `bifrost-http` and each `.so` with identical flags and `GOTOOLCHAIN=local`.
- Because the workspace uses the local `core/`/`framework/`, a patch to them reaches the host
  and every plugin.
- The image is Debian (glibc) based instead of Alpine; the dashboard is built with
  upstream's own `npm run build-enterprise`.

## Patches and plugins

- [`patches/`](patches/) -- **Bifrost source** patches, a quilt series applied to the whole
  monorepo with `--fuzz=0`.
- [`plugins/`](plugins/) -- **Go plugins**, one directory per plugin with a `plugin.conf`
  (GitHub repo + ref, or in-tree source), optional pre-build command, optional quilt series
  for the plugin source, and the config used by the smoke test.

Currently bundled: [`payload`](plugins/payload/plugin.conf)
([koreapyj/bifrost-plugin-payload](https://github.com/koreapyj/bifrost-plugin-payload), `main`).

## Image tags

| Tag | Meaning |
|-----|---------|
| `vX.Y.Z-<rev>` | upstream `vX.Y.Z` + patch set `<rev>` (immutable) |
| `vX.Y.Z-<rev>-amd64` / `-arm64` | per-arch images behind the tag above |
| `vX.Y.Z` | newest patch set for upstream `vX.Y.Z` |
| `latest` | newest stable upstream + newest patch set |

`<rev>` is the first 12 hex digits of a sha256 over `patches/`, `plugins/`, the **resolved
commit of every plugin**, and the build scripts ([`support/rev.sh`](support/rev.sh)). A plugin
that tracks a branch therefore produces a new `<rev>` (and a new image) whenever the branch
moves; README edits do not. The image's `org.opencontainers.image.description` label and
`/app/plugins/plugins.lock` record the plugin commits.

## CI: daily latest-stable tracking

[`.github/workflows/build.yaml`](.github/workflows/build.yaml) runs daily (and on push / PR /
manual dispatch):

1. **resolve** -- picks the newest `transports/vX.Y.Z` tag (pre-releases ignored), resolves
   each plugin's `REF` to a commit, computes `<rev>`, and skips everything if `vX.Y.Z-<rev>`
   is already published.
2. **build** -- downloads the tag, applies `patches/series` with `quilt push -a --fuzz=0`,
   stages the plugins at the resolved commits (applying their own series), builds the image
   natively on amd64 and arm64 runners, smoke-tests it, and pushes the per-arch image. The
   smoke test boots the image with every plugin enabled and requires `/health` and
   `GET /api/plugins` to report each plugin `active` -- a plugin that fails to load (toolchain
   or dependency mismatch) or rejects its config fails the run.
3. **manifest** -- publishes the multi-arch `vX.Y.Z-<rev>`, `vX.Y.Z` and `latest` tags.

Only the default branch publishes; PRs and other branches build and smoke-test amd64 only.
`workflow_dispatch` accepts `bifrost_version` (build a specific `vX.Y.Z`; never tagged
`latest`) and `force` (rebuild even if already published). Set the `PLUGINS_GH_TOKEN` secret
if a plugin repository is private.

**A failed run means work is needed**: a new upstream release moved code a patch touches,
a plugin no longer compiles against the new Bifrost, or a plugin commit broke loading.

## Local workflow

Requirements: `docker` (BuildKit), `make`, `quilt`, `curl`, `jq`, `tar`.
The [`Makefile`](Makefile) is local-only; CI calls the same `support/` scripts.

### Test the current state

```sh
make prepare      # download newest stable Bifrost into ./src/, apply patches/, stage plugins
make build        # docker build -f support/Dockerfile ./src -> bifrost-patched:local
make smoke        # same smoke test as CI
make run          # boot it at http://localhost:8080 with every plugin enabled (Ctrl-C to stop)
```

Use a local plugin checkout instead of its `REPO@REF`:

```sh
make prepare build smoke PLUGIN_SRC_payload=../bifrost-plugin-payload
```

### Author a Bifrost patch

```sh
make clean prepare
eval "$(make -s quilt-env)"            # QUILTRC/QUILT_PATCHES, cd src
quilt new 0001-my-change.patch         # numbering: see patches/README.md
quilt add core/bifrost.go              # before editing
quilt edit core/bifrost.go
quilt refresh
```

Plugin patches work the same with `PLUGIN=<name>` (see [`plugins/README.md`](plugins/README.md)).

### Move to a new upstream release (fix a failed CI run)

```sh
make clean prepare-src BIFROST_VERSION=vX.Y.Z   # download without applying patches
make refresh                                    # push each patch with fuzz allowed, then refresh
```

`make refresh` stops at the first patch that rejects; fix it (`quilt push -f`, resolve the
`.rej` hunks, `quilt refresh`) and re-run it. Then `make stage build smoke` and commit
`patches/`.

### Add a plugin

Create `plugins/<name>/plugin.conf` (keys in [`plugins/README.md`](plugins/README.md)), then
`make stage build smoke`.

### Variables

`BIFROST_VERSION` (default: newest stable), `IMAGE` (default `bifrost-patched:local`),
`DOCKER_BUILD_ARGS` (e.g. `--build-arg NODE_VERSION=22`, `--build-arg DEBIAN_SUITE=bookworm`),
`PLUGIN`, `PLUGIN_SRC_<name>`, and for `smoke`/`run` the environment variables
`BIFROST_PORT` and `SMOKE_TIMEOUT`. Run `make help` for the full list.
