# Unit tests run under busted (Lua 5.4; the code stays 5.4/5.5 portable).
# Install once: luarocks --local --lua-version 5.4 install busted
BUSTED ?= $(shell command -v busted 2>/dev/null || echo $(HOME)/.luarocks/bin/busted)
# The editor plugin's JavaScript (editor/*.js) is tested under node's own
# test runner; `make test` skips it, saying so, where node is missing.
NODE ?= $(shell command -v node 2>/dev/null)

.PHONY: test lua-test editor-test e2e
test: lua-test editor-test

lua-test:
	$(BUSTED)

editor-test:
ifeq ($(NODE),)
	@echo "editor-test: node not found, skipping editor/tests"
else
	$(NODE) --test editor/tests/
endif

# Nested Hyprland on a headless sway host; needs sway, foot, jq, gcc.
# One test: make e2e TESTS=e2e/smoke_test.sh
e2e:
	./e2e/run.sh $(TESTS)
