# Unit tests run under busted (Lua 5.4; the code stays 5.4/5.5 portable).
# Install once: luarocks --local --lua-version 5.4 install busted
BUSTED ?= $(shell command -v busted 2>/dev/null || echo $(HOME)/.luarocks/bin/busted)
# The editor plugin's JavaScript (editor/*.js) is tested under node's own
# test runner. `make editor-test` alone skips it, saying so, where node is
# missing; `make test` fails instead. Some of those tests run the engine's
# Lua (lua5.4, lua5.5 or lua) to pin the JavaScript against it: alone they
# skip without one, under `make test` (HYPRSLOTS_REQUIRE_LUA=1; busted needs
# Lua anyway) they fail.
NODE ?= $(shell command -v node 2>/dev/null)
# Its QML (Engine.qml's queue, debounce and watchdog; OpenFlow.qml's opening
# sequence) under Qt 6's qmltestrunner (/usr/bin/qmltestrunner may be Qt 5's),
# against stub Quickshell modules (editor/tests/qml/stubs), offscreen;
# `make test` skips it, saying so, where qmltestrunner is missing.
QMLTESTRUNNER ?= $(shell test -x /usr/lib/qt6/bin/qmltestrunner && echo /usr/lib/qt6/bin/qmltestrunner)

.PHONY: test lua-test editor-test editor-qml-test editor-lint e2e e2e-editor e2e-editor-multimon readme-shots
test: lua-test editor-test editor-qml-test
test: export HYPRSLOTS_REQUIRE_LUA := 1
test: REQUIRE_NODE := 1

# Hyprland runs Lua 5.5 (a for loop's variables are constants there):
# every file compiles under luac5.5 too, where it is installed.
LUAC55 ?= $(shell command -v luac5.5 2>/dev/null)
lua-test:
ifneq ($(LUAC55),)
	@for f in lua/hyprslots/*.lua tools/loader.lua; do $(LUAC55) -p "$$f" || exit 1; done
endif
	$(BUSTED)

# REQUIRE_NODE is set only under `make test`, a target-specific variable, so
# it is tested in the recipe's shell (ifeq is read before any target runs).
editor-test:
ifeq ($(NODE),)
	@if [ "$(REQUIRE_NODE)" = 1 ]; then \
	  echo "editor-test: node not found; make test needs it for editor/tests" >&2; exit 1; \
	fi; \
	echo "editor-test: node not found, skipping editor/tests"
else
	$(NODE) --test editor/tests/
endif

editor-qml-test:
ifeq ($(QMLTESTRUNNER),)
	@echo "editor-qml-test: Qt 6 qmltestrunner not found, skipping editor/tests/qml"
else
	QT_QPA_PLATFORM=offscreen $(QMLTESTRUNNER) -import editor/tests/qml/stubs -input editor/tests/qml
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
# `make e2e`); needs qs, grim and wtype: the smoke, a fresh install's first
# run, the Desk tab's desk maps on two screens, the Layout tab's screens
# swapped by drag and by p, its slots dragged by the mouse, the engine
# enabled from the editor on a plugin just added, and windows arranged by
# hand captured as slots, then launched again. Screenshots:
# .e2e-tmp/editor-smoke-*.png, .e2e-tmp/editor-first-run-*.png,
# .e2e-tmp/editor-desk-map-*.png, .e2e-tmp/editor-screen-swap-*.png,
# .e2e-tmp/editor-slot-drag-*.png, .e2e-tmp/editor-install-*.png,
# .e2e-tmp/editor-capture-*.png
e2e-editor:
	./e2e/run.sh e2e/editor_smoke.sh e2e/editor_first_run.sh e2e/editor_desk_map.sh e2e/editor_screen_swap.sh \
	  e2e/editor_slot_drag.sh e2e/editor_install.sh e2e/editor_capture.sh

# The editor on a 2-screen desk, screenshots only (opt-in, like e2e-editor):
# into $MULTIMON_SHOTS (default .e2e-tmp/multimon/latest).
e2e-editor-multimon:
	./e2e/run.sh e2e/editor_multimon.sh

# The README's screenshots (opt-in, no gate runs it): a staged demo on the
# nested Hyprland, into docs/screenshots/ (and preview.png, the Layout
# tab); needs qs, grim, magick, nvim, bat and glow. README_SHOTS_LIGHT is
# the light theme of layout-tab-light.png.
README_SHOTS_LIGHT ?= $(OMARCHY_PATH)/themes/catppuccin-latte
readme-shots:
	README_SHOTS_LIGHT=$(README_SHOTS_LIGHT) ./e2e/run.sh e2e/readme_shots.sh
