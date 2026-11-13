# patches/

Quilt patch series applied on top of upstream [Bifrost](https://github.com/maximhq/bifrost)
(the whole monorepo at tag `transports/vX.Y.Z`) before the image is built. `series` lists
the patches in application order; an empty `series` builds stock upstream.

This directory **is** the quilt patch directory, so `quilt new` / `quilt refresh` write here
directly -- no copy-back step.

The image is built in one Go workspace containing `core/`, `framework/`, `transports/` and
`plugins/*` of the patched tree (see `support/build.sh`), so a patch to any of them reaches
`bifrost-http` **and** every bundled plugin. Patches to `ui/` reach the dashboard.

## Authoring

```sh
make clean prepare
eval "$(make -s quilt-env)"            # QUILTRC, QUILT_PATCHES, cd src
quilt new 0001-my-change.patch         # see "Numbering" below
quilt add core/bifrost.go              # before editing!
quilt edit core/bifrost.go             # ... make changes ...
quilt refresh
cd -; make build smoke
```

## Numbering

The number range says what kind of patch it is (and therefore what to do with it when
upstream changes). Within a range, number sequentially; `series` lists patches in
ascending order.

| Range | Kind |
|---|---|
| `0001`-`0999` | Standalone fixes: self-contained, could go upstream; drop once upstream fixes it. |
| `1000`-`1999` | Other patches that fit none of the ranges below. |
| `6000`-`6999` | Needed by a bundled plugin (an API or hook the plugin relies on); add/remove together with the plugin. |
| `9000`-`9999` | Local-only or local policy (builder infrastructure, behaviour we choose to differ from upstream). |

## Strict application (fuzz = 0)

CI applies the series with `quilt push -a --fuzz=0` (`support/apply-patches.sh`). Any patch
that needs fuzz or rejects fails the build. Because CI follows the newest stable upstream
release daily, a failed scheduled run usually means a new release moved code our patches
touch. To fix it:

```sh
make clean prepare-src BIFROST_VERSION=vX.Y.Z   # download the new release, no patches
make refresh                                    # push each patch (fuzz allowed) and refresh it
```

`make refresh` stops at the first patch that rejects; resolve it by hand (`quilt push -f`,
fix the `.rej` hunks, `quilt refresh`) and re-run `make refresh`.
