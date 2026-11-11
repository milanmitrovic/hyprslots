# Unit tests run under busted (Lua 5.4; the code stays 5.4/5.5 portable).
# Install once: luarocks --local --lua-version 5.4 install busted
BUSTED ?= $(shell command -v busted 2>/dev/null || echo $(HOME)/.luarocks/bin/busted)
# The editor plugin's JavaScript (editor/*.js) is tested under node's own
# test runner; `make test` skips it, saying so, where node is missing.
NODE ?= $(shell command -v node 2>/dev/null)

.PHONY: test lua-test editor-test editor-lint e2e e2e-editor e2e-editor-multimon
test: lua-test editor-test

lua-test:
	$(BUSTED)

editor-test:
ifeq ($(NODE),)
	@echo "editor-test: node not found, skipping editor/tests"
else
	$(NODE) --test editor/tests/
endif

# qmllint (Qt 6's; /usr/bin/qmllint is Qt 5's) over the plugin, with qs.Commons
# and qs.Ui resolved against Omarchy's shell. qmllint cannot see into
# Style's nested QtObjects, so its "not found on type QObject" warnings are
# filtered out, as is its claim that editor/ui/Tokens.qml is no singleton
# (ui/qmldir declares it one; qmllint misreads it when linting the file
# itself).
QMLLINT ?= /usr/lib/qt6/bin/qmllint
OMARCHY_PATH ?= /usr/share/omarchy
editor-lint:
	@mkdir -p .e2e-tmp/lint-imports && ln -sfn $(OMARCHY_PATH)/shell .e2e-tmp/lint-imports/qs
	@$(QMLLINT) -I .e2e-tmp/lint-imports editor/*.qml editor/ui/*.qml 2>&1 \
	  | grep -E '^(Warning|Error)' | grep -v -e 'not found on type "QObject"' -e 'Type Tokens not declared as singleton' || true

# Nested Hyprland on a headless sway host; needs sway, foot, jq, gcc.
# One test: make e2e TESTS=e2e/smoke_test.sh
e2e:
	./e2e/run.sh $(TESTS)

# The editor plugin in Quickshell on the nested Hyprland (opt-in: not part of
# `make e2e`); needs qs, grim and wtype. Screenshots: .e2e-tmp/editor-smoke-*.png
e2e-editor:
	./e2e/run.sh e2e/editor_smoke.sh

# The editor on a 2-screen desk, screenshots only (opt-in, like e2e-editor):
# into $MULTIMON_SHOTS (default .e2e-tmp/multimon/latest).
e2e-editor-multimon:
	./e2e/run.sh e2e/editor_multimon.sh
