# NVIM is Neovim's server socket in terminal jobs, not an executable.
NVIM_BIN ?= nvim
ZALS_BIN ?= zals

.PHONY: help check check-all test integration integrations integration-roles

help:
	@echo 'make check                         Lua syntax, configuration, filetype and attachment tests'
	@echo 'make check-all                     check + real-server integration tests'
	@echo 'make integration[s] ZALS_BIN=/path/to/zals  tests with a real server'
	@echo 'make integration-roles ZALS_BIN=/path/to/zals  require role commands; no skips'

check:
	git diff --check
	$(NVIM_BIN) --headless -u NONE -i NONE -n -l tests/check.lua

test: check

check-all: check integration

integrations: integration

integration:
	ZALS_BIN="$(ZALS_BIN)" $(NVIM_BIN) --headless -u NONE -i NONE -n -l tests/integration.lua

integration-roles:
	ZALS_REQUIRE_ROLES=1 ZALS_BIN="$(ZALS_BIN)" $(NVIM_BIN) --headless -u NONE -i NONE -n -l tests/integration.lua
