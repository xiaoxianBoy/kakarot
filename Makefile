# Include .env file to get GITHUB_TOKEN
ifneq ("$(wildcard .env)","")
    include .env
    export $(shell sed 's/=.*//' .env)
endif

.PHONY: build test coverage

# Kakarot SSJ artifacts for precompiles
KKRT_SSJ_BUILD_ARTIFACT_URL = $(shell curl -L https://api.github.com/repos/kkrt-labs/kakarot-ssj/releases/latest | jq -r '.assets[0].browser_download_url')
KATANA_VERSION = v0.7.0-alpha.0
build: check
	$(MAKE) clean
	poetry run python ./kakarot_scripts/compile_kakarot.py

check:
	poetry check --lock

fetch-ef-tests:
	poetry run python ./kakarot_scripts/ef_tests/fetch.py

# This action fetches the latest Kakarot SSJ (Cairo compiler version >=2) artifacts
# from the main branch and unzips them into the build/ssj directory.
# This is required because Kakarot Zero (Cairo Zero, compiler version <1) uses some SSJ Cairo programs.
# Most notably for precompiles.
fetch-ssj-artifacts:
	rm -rf build/ssj
	mkdir -p build/ssj
	@curl -sL -o dev-artifacts.zip "$(KKRT_SSJ_BUILD_ARTIFACT_URL)"
	unzip -o dev-artifacts.zip -d build/ssj
	rm -f dev-artifacts.zip

setup: fetch-ssj-artifacts
	poetry install

test: build-sol deploy
	poetry run pytest tests/src -m "not NoCI" --log-cli-level=INFO -n logical
	poetry run pytest tests/end_to_end

test-unit: build-sol
	poetry run pytest tests/src -m "not NoCI" -n logical

test-end-to-end: build-sol deploy
	poetry run pytest tests/end_to_end

deploy: build
	poetry run python ./kakarot_scripts/deploy_kakarot.py

format:
	trunk check --fix

format-check:
	trunk check --ci

clean:
	rm -rf build/*.json
	rm -rf build/fixtures/*.json
	mkdir -p build

check-resources:
	poetry run python kakarot_scripts/check_resources.py

build-sol:
	git submodule update --init --recursive
	forge build --names --force
	$(MAKE) build-sol-experimental

build-sol-experimental:
	docker run --rm \
		-v $$(pwd):/app/foundry \
		-u $$(id -u):$$(id -g) \
		ghcr.io/paradigmxyz/foundry-alphanet@sha256:64ac81c19b910e766ce750499a2c9de064dce4fa9c4fc1e42368fdd73fc48dde \
		--foundry-directory /app/foundry/experimental_contracts \
		--foundry-command build



install-katana:
	cargo install --git https://github.com/dojoengine/dojo --locked --tag "${KATANA_VERSION}" katana

run-katana:
	katana --chain-id test --validate-max-steps 6000000 --invoke-max-steps 14000000 --eth-gas-price 0 --strk-gas-price 0 --disable-fee
