.PHONY: init
init:
	sh ./scripts/init.sh

.PHONY: lint
lint:
	luacheck ./lua

.PHONY: test
test:
	NVIM_LISTEN_ADDRESS=/tmp/nvimvusted vusted --output=gtest --pattern=.spec ./lua

.PHONY: pre-commit
pre-commit:
	luacheck lua
	vusted lua

.PHONY: check
check:
	make lint
	make test

