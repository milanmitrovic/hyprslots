// lua.mjs: the tests that pin the editor's models against the engine's Lua
// skip, saying so, without a Lua interpreter, and fail instead where one is
// required (HYPRSLOTS_REQUIRE_LUA=1, as `make test` sets it).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { CANDIDATES, findLua } from "./lua.mjs";

const none = () => false;

test("the first interpreter that runs is the one used, in the order lua5.4, lua5.5, lua", () => {
  assert.deepEqual(CANDIDATES, ["lua5.4", "lua5.5", "lua"]);
  assert.equal(findLua({}, (bin) => bin !== "lua5.4").bin, "lua5.5");
  assert.equal(findLua({}, (bin) => bin === "lua").bin, "lua");
  assert.equal(findLua({}, () => true).bin, "lua5.4");
});

test("with an interpreter, nothing skips, required or not", () => {
  assert.equal(findLua({}, () => true).skip, false);
  assert.equal(findLua({ HYPRSLOTS_REQUIRE_LUA: "1" }, () => true).skip, false);
});

test("without one, the tests skip, saying what was looked for and how to fail instead", () => {
  const found = findLua({}, none);
  assert.equal(found.bin, undefined);
  assert.equal(found.required, false);
  assert.match(found.skip, /no lua \(lua5\.4, lua5\.5, lua\)/);
  assert.match(found.skip, /HYPRSLOTS_REQUIRE_LUA=1 fails instead/);
});

test("without one where it is required, nothing skips: the tests run, and fail", () => {
  const found = findLua({ HYPRSLOTS_REQUIRE_LUA: "1" }, none);
  assert.equal(found.required, true);
  assert.equal(found.skip, false);
  // only "1" requires it
  for (const value of ["", "0", "yes", undefined]) {
    assert.equal(findLua({ HYPRSLOTS_REQUIRE_LUA: value }, none).required, false, String(value));
  }
});

// The whole path: a contract test file run by node with no Lua on PATH.
const here = dirname(fileURLToPath(import.meta.url));
const runWithoutLua = (env) => {
  const empty = mkdtempSync(join(tmpdir(), "hyprslots-no-lua-"));
  try {
    return spawnSync(process.execPath, ["--test", "--test-reporter=tap", join(here, "layout-drag.test.mjs")],
      { env: { ...env, PATH: empty }, encoding: "utf8" });
  } finally {
    rmSync(empty, { recursive: true });
  }
};

test("run without Lua, the contract test skips; required, it fails naming the missing interpreter", () => {
  // without the runner's own variables, which would make the child report to
  // this runner instead of printing TAP
  const { HYPRSLOTS_REQUIRE_LUA: _, NODE_TEST_CONTEXT: __, NODE_TEST_WORKER_ID: ___, ...env } = process.env;
  const skipped = runWithoutLua(env);
  assert.equal(skipped.status, 0, skipped.stdout + skipped.stderr);
  assert.match(skipped.stdout, /# SKIP no lua/);
  assert.match(skipped.stdout, /^# fail 0$/m);

  const failed = runWithoutLua({ ...env, HYPRSLOTS_REQUIRE_LUA: "1" });
  assert.notEqual(failed.status, 0, failed.stdout);
  assert.match(failed.stdout, /HYPRSLOTS_REQUIRE_LUA=1 and no Lua interpreter found/);
  assert.match(failed.stdout, /^# fail 1$/m);
  assert.doesNotMatch(failed.stdout, /# SKIP/);
});
