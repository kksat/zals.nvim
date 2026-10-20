# NVIM is Neovim's server socket in terminal jobs, not an executable.
NVIM_BIN ?= nvim
ZALS_BIN ?= zals

.PHONY: help check test integration

help:
	@echo 'make check                         Lua syntax, configuration, filetype and attachment tests'
	@echo 'make integration ZALS_BIN=/path/to/zals  references test with a real server'

check:
	git diff --check
	$(NVIM_BIN) --headless -u NONE -i NONE -n -l tests/check.lua

test: check

integration:
	ZALS_BIN="$(ZALS_BIN)" $(NVIM_BIN) --headless -u NONE -i NONE -n -l tests/integration.lua
