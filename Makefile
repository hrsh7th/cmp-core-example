DENO_DIR := ${PWD}/.deno_dir

.PHONY: prepare
prepare:
	docker build --platform linux/arm64/v8 -t panvimdoc https://github.com/kdheepak/panvimdoc.git#d5b6a1f3ab0cb2c060766e7fd426ed32c4b349b2

.PHONY: lint
lint:
	docker run -v $(PWD):/code -i registry.gitlab.com/pipeline-components/luacheck:latest --codes /code/lua

.PHONY: format
format:
	docker run -v $(PWD):/src -i fnichol/stylua --config-path=/src/.stylua.toml -- /src/lua

.PHONY: test
test:
	vusted --output=gtest --pattern=.spec ./lua

.PHONY: check
check:
	make lint
	make format
	make test

