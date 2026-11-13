# Local-only patch-authoring and test-build workflow for the patched Bifrost image.
# GitHub Actions does NOT use this Makefile -- see .github/workflows/build.yaml
# (it calls the same support/ scripts, so local and CI behave the same).

SHELL := /bin/bash

# Empty = newest stable vX.Y.Z (tag transports/vX.Y.Z), resolved by support/latest-tag.sh.
BIFROST_VERSION ?=

SRC     := src
WORK    := .work
LOCK    := $(WORK)/plugins.lock
PATCHES := patches
QUILTRC := $(CURDIR)/.quiltrc
IMAGE   ?= bifrost-patched:local
# Extra arguments for `docker build`, e.g. DOCKER_BUILD_ARGS='--build-arg NODE_VERSION=22'
DOCKER_BUILD_ARGS ?=
# `make refresh PLUGIN=<name>` / `make quilt-env PLUGIN=<name>` target a plugin's series.
PLUGIN ?=

ifeq ($(PLUGIN),)
  QUILT_TREE    := $(SRC)
  QUILT_SERIES  := $(PATCHES)
else
  QUILT_TREE    := $(SRC)/.builder/plugins/$(PLUGIN)
  QUILT_SERIES  := plugins/$(PLUGIN)/patches
endif

.DEFAULT_GOAL := help
.PHONY: help prepare-src prepare stage build smoke run refresh quilt-env rev clean clean-image

help:
	@echo 'Local patch-authoring / test-build workflow (not used by CI).'
	@echo
	@echo 'Targets:'
	@echo '  prepare-src        download Bifrost into $(SRC)/ (no patches applied)'
	@echo '  prepare            prepare-src + apply $(PATCHES)/series (fuzz=0) + resolve and stage plugins'
	@echo '  stage              re-resolve and re-stage plugins only (after editing plugins/ or a local plugin)'
	@echo '  build              docker build support/Dockerfile from $(SRC)/ -> $(IMAGE)'
	@echo '  smoke              boot $(IMAGE), check /health and that every plugin is active (same as CI)'
	@echo '  run                boot $(IMAGE) in the foreground (http://localhost:8080)'
	@echo '  refresh [PLUGIN=name]'
	@echo '                     re-push every patch with fuzz allowed and quilt-refresh it'
	@echo '                     (Bifrost series, or plugins/<name>/patches with PLUGIN)'
	@echo '  quilt-env [PLUGIN=name]'
	@echo '                     print the environment for authoring patches with quilt'
	@echo '  rev                print the patch-set revision for the current $(LOCK)'
	@echo '  clean              remove $(SRC)/ and $(WORK)/'
	@echo '  clean-image        remove $(IMAGE)'
	@echo
	@echo 'Variables: BIFROST_VERSION (default: newest stable), IMAGE (default $(IMAGE)),'
	@echo '           DOCKER_BUILD_ARGS, PLUGIN, PLUGIN_SRC_<name>=<dir> (use a local plugin checkout)'
	@echo
	@echo 'Test build:       make prepare build smoke'
	@echo 'Local plugin:     make prepare build smoke PLUGIN_SRC_payload=../bifrost-plugin-payload'
	@echo 'New upstream:     make clean prepare-src BIFROST_VERSION=vX.Y.Z  ->  make refresh'

$(SRC)/transports/go.mod:
	@set -e; v='$(BIFROST_VERSION)'; \
	if [ -z "$$v" ]; then v=$$(bash support/latest-tag.sh); fi; \
	bash support/fetch-bifrost.sh "$$v" $(SRC)

prepare-src: $(SRC)/transports/go.mod

prepare: prepare-src
	bash support/apply-patches.sh $(SRC) $(PATCHES)
	@$(MAKE) --no-print-directory stage

stage:
	@test -f $(SRC)/transports/go.mod || { echo "No $(SRC)/ -- run 'make prepare' first"; exit 1; }
	@mkdir -p $(WORK)
	bash support/plugins.sh resolve $(LOCK)
	bash support/plugins.sh stage $(SRC) $(LOCK)

build:
	bash support/build-image.sh $(SRC) '$(IMAGE)' $(DOCKER_BUILD_ARGS)

smoke:
	bash support/smoke.sh '$(IMAGE)'

run:
	bash support/smoke.sh --run '$(IMAGE)'

refresh:
	@test -d $(QUILT_TREE) || { echo "No $(QUILT_TREE)/ -- run 'make prepare-src' (or 'make prepare' for a plugin) first"; exit 1; }
	bash support/refresh.sh $(QUILT_TREE) $(QUILT_SERIES)

quilt-env:
	@mkdir -p $(QUILT_SERIES) && touch $(QUILT_SERIES)/series
	@echo 'export QUILTRC=$(QUILTRC) QUILT_PATCHES=$(CURDIR)/$(QUILT_SERIES)'
	@echo 'cd $(CURDIR)/$(QUILT_TREE)'
	@echo '# quilt new <NNNN-name>.patch ; quilt add <file> ; quilt edit <file> ; quilt refresh'

rev:
	@test -f $(LOCK) || { echo "No $(LOCK) -- run 'make stage' first"; exit 1; }
	@bash support/rev.sh $(LOCK)

clean:
	rm -rf $(SRC) $(WORK)

clean-image:
	-docker image rm '$(IMAGE)'
