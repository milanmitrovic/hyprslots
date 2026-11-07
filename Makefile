# Unit tests run under busted (Lua 5.4; the code stays 5.4/5.5 portable).
# Install once: luarocks --local --lua-version 5.4 install busted
BUSTED ?= $(shell command -v busted 2>/dev/null || echo $(HOME)/.luarocks/bin/busted)

.PHONY: test e2e
test:
	$(BUSTED)

# Nested Hyprland on a headless sway host; needs sway, foot, jq, gcc.
# One test: make e2e TESTS=e2e/smoke_test.sh
e2e:
	./e2e/run.sh $(TESTS)
