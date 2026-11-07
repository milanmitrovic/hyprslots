// Load one of the plugin's QML JavaScript libraries (`.pragma library`, no
// exports) into a fresh context, so node can test its functions.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));

export function load(name) {
  const source = readFileSync(join(here, "..", name), "utf8").replace(/^\.pragma library$/m, "");
  const context = vm.createContext({});
  vm.runInContext(source, context, { filename: name });
  return context;
}
