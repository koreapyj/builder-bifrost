# plugins/

Go plugins (`-buildmode=plugin`) bundled into the image. Each subdirectory with a
`plugin.conf` is one plugin; it is compiled in the same Go workspace, with the same
toolchain and flags as `bifrost-http`, and installed at `/app/plugins/<name>.so`.

Go refuses to load a plugin into a host built from different package sources, dependency
versions or toolchain (`plugin was built with a different version of package ...`), and
official Bifrost binaries are statically linked and cannot load plugins at all. Building
both in one place is the reason this repository exists.

## Layout

```
plugins/<name>/
  plugin.conf        required; sourced by bash (see below)
  patches/series     optional quilt series applied to the plugin source (fuzz=0)
  patches/*.patch
  src/               optional in-tree plugin source (used when REPO is empty)
```

`<name>` (`[a-z0-9_-]`) is the `.so` file name and the `name` used in the smoke-test config.

## plugin.conf

| Key | Default | Meaning |
|---|---|---|
| `REPO` | -- | GitHub `owner/repo` of the plugin. Empty: build `plugins/<name>/src/`. |
| `REF` | -- | Branch, tag or commit (required with `REPO`). Resolved to a commit once per CI run; that commit is part of the patch-set revision, so a branch REF rebuilds the image whenever the branch moves. Pin a tag or commit for reproducible builds. |
| `PACKAGE` | `.` | Go package (relative to the plugin root) built with `-buildmode=plugin`. |
| `PREBUILD` | -- | Shell command run in the plugin root before compiling (e.g. generating embedded assets). Go and Node.js/npm are available; `GOWORK` points at the shared workspace. |
| `SMOKE_CONFIG` | `{}` | JSON `config` for the plugin in the smoke test. The smoke test requires every plugin to report `active`, i.e. `Init` must accept this config. |

The plugin's `go.mod` may pin any `bifrost/core` version: in the workspace the patched
`core/` of the Bifrost tree replaces it. The Go toolchain used is the highest `go` /
`toolchain` version of all workspace modules, so a plugin can raise it but never lower it.

## Private plugin repositories

The workflow's `GITHUB_TOKEN` can only read this repository. For private plugin
repositories elsewhere, add a token with read access as the `PLUGINS_GH_TOKEN` secret.

## Developing a plugin against this build

```sh
make prepare build smoke PLUGIN_SRC_payload=../bifrost-plugin-payload
```

`PLUGIN_SRC_<name>` (dashes become underscores) uses a local checkout instead of
`REPO@REF`. Plugin patches are authored like Bifrost patches, against the staged copy:

```sh
make prepare
eval "$(make -s quilt-env PLUGIN=payload)"   # cd src/.builder/plugins/payload
quilt new 0001-my-change.patch ; quilt add main.go ; quilt edit main.go ; quilt refresh
```

A failing plugin patch after a plugin update is fixed with `make refresh PLUGIN=<name>`.
