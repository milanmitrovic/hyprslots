// The Lua interpreter the tests that pin the editor's models against the
// engine's own modules (tree.lua, ratio.lua, serialize.lua) run them under.
// Without one those tests skip, saying so; with HYPRSLOTS_REQUIRE_LUA=1 (as
// `make test` sets it, where busted needs Lua anyway) they fail instead, so a
// run with node but no Lua cannot pass with the JS/Lua agreement unchecked.
import { spawnSync } from "node:child_process";

export const CANDIDATES = ["lua5.4", "lua5.5", "lua"];

// The first candidate that runs, whether one is required, and the test
// option that skips without one (false where one is found or required).
export function findLua(env = process.env, runs = (bin) => spawnSync(bin, ["-v"]).status === 0) {
  const bin = CANDIDATES.find(runs);
  const required = env.HYPRSLOTS_REQUIRE_LUA === "1";
  return {
    bin,
    required,
    skip: !bin && !required && "no lua (" + CANDIDATES.join(", ") + "); HYPRSLOTS_REQUIRE_LUA=1 fails instead",
  };
}

const found = findLua();

// For a test's options: { skip: skipWithoutLua }.
export const skipWithoutLua = found.skip;

// The interpreter, inside a test; throws, naming what was looked for, where
// there is none (reached only when one is required).
export function luaBin() {
  if (!found.bin) {
    throw new Error("HYPRSLOTS_REQUIRE_LUA=1 and no Lua interpreter found (looked for "
      + CANDIDATES.join(", ") + " on PATH)");
  }
  return found.bin;
}
