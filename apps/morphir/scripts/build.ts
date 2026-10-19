import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const appDirectory = fileURLToPath(new URL("../", import.meta.url));
const buildDirectory = fileURLToPath(new URL("../_build/", import.meta.url));

execFileSync(
  "moon",
  ["build", ".", "../../pkgs/morphir-host/connected-core", "--target", "js", "--release", "--target-dir", buildDirectory],
  { cwd: appDirectory, stdio: "inherit" },
);

mkdirSync(new URL("../dist/", import.meta.url), { recursive: true });
copyFileSync(
  new URL("../_build/js/release/build/morphir/morphir/morphir.js", import.meta.url),
  new URL("../dist/morphir.js", import.meta.url),
);
copyFileSync(
  new URL("../_build/js/release/build/finos/morphir-host/connected-core/connected-core.js", import.meta.url),
  new URL("../dist/connected-core.js", import.meta.url),
);

await import("../../../tools/build-runtimes.ts");
