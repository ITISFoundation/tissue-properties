# Build, run, version-bump and publish helpers for the tissue-properties
# o²S²PARC service. Mirrors the layout used by ITISFoundation/mmux_vite.

SHELL := /bin/bash
.DEFAULT_GOAL := help

export DOCKER_IMAGE_NAME ?= tissue-properties
export DOCKER_IMAGE_TAG  ?= 1.0.4
export DOCKER_REGISTRY   ?= itisfoundation

OOIL_IMAGE := itisfoundation/ci-service-integration-library:v2.2.4


.PHONY: help
help: ## list targets
	@echo "Recipes for '$(notdir $(CURDIR))' (version $(DOCKER_IMAGE_TAG)):"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[[:alpha:][:space:]_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' \
		$(MAKEFILE_LIST)
	@echo ""


.PHONY: compose-spec
compose-spec: ## generates docker-compose.yml from .osparc/ via ooil
	@docker run -it --rm -v $(PWD):/$(DOCKER_IMAGE_NAME) \
		-u $(shell id -u):$(shell id -g) \
		$(OOIL_IMAGE) \
		sh -c "cd /$(DOCKER_IMAGE_NAME) && ooil compose"


.PHONY: build
build: compose-spec ## build the production image
	docker compose build

.PHONY: build-devel
build-devel: ## build the development image (Vite + HMR)
	docker build --target development \
		-t $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)-devel \
		.

.PHONY: run
run: build ## build & run the production image (validates as it would in oSPARC)
	docker compose --file docker-compose-local.yml up

.PHONY: run-devel
run-devel: build-devel ## build & run the development image with hot-reload bind-mounts
	docker compose --file docker-compose-development.yml up

.PHONY: down
down: ## stop the local stack (works for both prod and dev)
	-docker compose --file docker-compose-local.yml down
	-docker compose --file docker-compose-development.yml down


.PHONY: publish-local
publish-local: ## tag + push to the local throw-away registry (requires `make build`)
	docker tag \
		simcore/services/dynamic/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) \
		registry:5000/simcore/services/dynamic/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
	docker push \
		registry:5000/simcore/services/dynamic/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
	@curl -fsS registry:5000/v2/_catalog | jq


define _bumpversion
	@docker run -it --rm -v $(PWD):/$(DOCKER_IMAGE_NAME) \
		-u $(shell id -u):$(shell id -g) \
		$(OOIL_IMAGE) \
		sh -c "cd /$(DOCKER_IMAGE_NAME) && bump2version --verbose --list --config-file $(1) $(subst $(2),,$@)"
endef

.PHONY: version-patch
.PHONY: version-minor
.PHONY: version-major
version-patch version-minor version-major: .bumpversion.cfg ## bump service version (patch/minor/major)
	@$(MAKE) compose-spec
	$(call _bumpversion,$<,version-)
	@$(MAKE) compose-spec


# ============================================================================
# Tissue properties data pipeline
# ----------------------------------------------------------------------------

DB_TOOLS_IMAGE := tissue-properties/db-tools:local
# data-source/ is expected to contain exactly ONE .db file. The targets
# below enforce that and pick it up automatically. To use a different
# file, replace the one in data-source/ or pass DB=path/to/file.db.
DB             ?= $(firstword $(wildcard data-source/*.db))
OUT_CSV        ?= src/csv-to-html-table/data/TissueProperties.csv
VERSION        ?=

# Bail out unless data-source/ contains exactly one .db file (or DB=...
# was passed explicitly on the command line).
_db_count       = $(words $(wildcard data-source/*.db))
define _check_db
@if [ "$(origin DB)" = "file" ] && [ $(_db_count) -ne 1 ]; then \
	echo "ERROR: data-source/ must contain exactly one .db file (found $(_db_count))."; \
	echo "       Either keep a single .db in data-source/ or pass DB=path/to/file.db."; \
	exit 1; \
fi
@test -n "$(DB)" || { echo "ERROR: no .db file found. Drop one in data-source/ or pass DB=path/to/file.db"; exit 1; }
@test -f "$(DB)" || { echo "ERROR: DB file not found: $(DB)"; exit 1; }
endef

# Internal: helper image used by tissues-list-versions / tissues-update-csv.
# Built on first use and cached by docker; not surfaced in `make help`.
.PHONY: tissues-build-tools
tissues-build-tools: scripts/Dockerfile scripts/tissues_db.py
	docker build -t $(DB_TOOLS_IMAGE) scripts/

# Run the helper image. $(1) is the CLI command + args appended to the entrypoint.
define _db_tools_run
docker run --rm \
	-v "$(PWD)":/work -w /work \
	-u $(shell id -u):$(shell id -g) \
	$(DB_TOOLS_IMAGE) $(1)
endef

.PHONY: tissues-list-versions
tissues-list-versions: tissues-build-tools ## list IT'IS versions in $(DB) and their tissue counts
	$(_check_db)
	@echo "[tissues-list-versions] DB: $(DB)"
	@$(call _db_tools_run,list-versions "$(DB)")

.PHONY: tissues-update-csv
tissues-update-csv: tissues-build-tools ## regenerate $(OUT_CSV) from $(DB) and update version_display in metadata.yml (REQUIRED: VERSION=4.0 etc)
	$(_check_db)
	@test -n "$(VERSION)" || { echo "ERROR: VERSION is required, e.g. 'make tissues-update-csv VERSION=4.0'"; exit 1; }
	@echo "[tissues-update-csv] DB: $(DB)"
	@$(call _db_tools_run,convert "$(DB)" "$(OUT_CSV)" --version "$(VERSION)")
	@$(MAKE) compose-spec
