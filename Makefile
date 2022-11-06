.PHONY: fmt
fmt:
	stylua --config-path stylua.toml --glob 'lua/**/*.lua' -- lua

.PHONY: lint
lint:
	luacheck ./lua

.PHONY: test
test:
	vusted --output=gtest --pattern=.spec ./lua

.PHONY: prepare
prepare:
	if [ ! -e "./tmp/nvim-treesitter" ]; then git clone git@github.com:nvim-treesitter/nvim-treesitter ./tmp/nvim-treesitter; fi
	git -C ./tmp/nvim-treesitter pull --rebase
	if [ ! -e "./tmp/language-server-protocol" ]; then git clone git@github.com:microsoft/language-server-protocol ./tmp/language-server-protocol; fi
	git -C ./tmp/language-server-protocol pull --rebase

