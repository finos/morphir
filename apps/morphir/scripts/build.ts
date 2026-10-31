import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const appDirectory = fileURLToPath(new URL("../", import.meta.url));
const buildDirectory = fileURLToPath(new URL("../_build/", import.meta.url));

execFileSync(
  "moon",
  ["build", "node", "../../pkgs/morphir-host/connected-core", "../../pkgs/morphir-host/worker/thread/entry", "--target", "js", "--release", "--target-dir", buildDirectory],
  // Build summaries must not corrupt npm pack --json during prepack.
  { cwd: appDirectory, stdio: ["inherit", 2, 2] },
);

mkdirSync(new URL("../dist/", import.meta.url), { recursive: true });
copyFileSync(
  new URL("../_build/js/release/build/morphir/morphir/node/node.js", import.meta.url),
  new URL("../dist/morphir.js", import.meta.url),
);
copyFileSync(
  new URL("../_build/js/release/build/finos/morphir-host/connected-core/connected-core.js", import.meta.url),
  new URL("../dist/connected-core.js", import.meta.url),
);
// The Node worker-thread entry of WASM guests, beside the CLI bundle.
copyFileSync(
  new URL("../_build/js/release/build/finos/morphir-host/worker/thread/entry/entry.js", import.meta.url),
  new URL("../dist/wasm-worker.js", import.meta.url),
);

await import("../../../tools/build-runtimes.ts");
