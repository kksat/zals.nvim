NVIM ?= nvim
ZALS_BIN ?= zals

.PHONY: help check test integration

help:
	@echo 'make check                         Lua syntax, configuration, filetype and attachment tests'
	@echo 'make integration ZALS_BIN=/path/to/zals  references test with a real server'

check:
	git diff --check
	$(NVIM) --headless -u NONE -i NONE -n -l tests/check.lua

test: check

integration:
	ZALS_BIN="$(ZALS_BIN)" $(NVIM) --headless -u NONE -i NONE -n -l tests/integration.lua
