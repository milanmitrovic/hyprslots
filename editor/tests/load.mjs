// Load one of the plugin's QML JavaScript libraries (`.pragma library`, no
// exports) into a fresh context, so node can test its functions. A library's
// `.import "Other.js" as Name` loads Other.js the same way, as `Name` in it.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));

export function load(name) {
  const imports = {};
  const source = readFileSync(join(here, "..", name), "utf8")
    .replace(/^\.pragma library$/m, "")
    .replace(/^\.import "([^"]+\.js)" as (\w+)$/gm, (_, file, as) => {
      imports[as] = load(file);
      return "";
    });
  const context = vm.createContext(imports);
  vm.runInContext(source, context, { filename: name });
  return context;
}
