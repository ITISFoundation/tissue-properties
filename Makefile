# Build, run, version-bump and publish helpers for the tissue-properties
# o²S²PARC service. Mirrors the layout used by ITISFoundation/mmux_vite.

SHELL := /bin/bash
.DEFAULT_GOAL := help

export DOCKER_IMAGE_NAME ?= tissue-properties
export DOCKER_IMAGE_TAG  ?= 1.0.2
export DOCKER_REGISTRY   ?= itisfoundation

OOIL_IMAGE := itisfoundation/ci-service-integration-library:v2.2.24


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

.PHONY: run-local
run-local: ## run the production image (validates as it would in oSPARC)
	docker compose --file docker-compose-local.yml up

.PHONY: run-devel
run-devel: ## run the development image with hot-reload bind-mounts
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

.PHONY: help
help: ## list targets
	@echo "Recipes for '$(notdir $(CURDIR))' (version $(DOCKER_IMAGE_TAG)):"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[[:alpha:][:space:]_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' \
		$(MAKEFILE_LIST)
	@echo ""
