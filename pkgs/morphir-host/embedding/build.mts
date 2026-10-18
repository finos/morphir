import { execFileSync } from "node:child_process";
import {checkedBuild} from "../../../tools/build.ts";
import {fileURLToPath} from "node:url";
import {readFile, mkdir, copyFile} from "node:fs/promises";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const compilerPath = require.resolve("@moonbit/moonc-worker");
const source = await readFile(compilerPath, "utf8");

// Ship the pure MoonBit planner with the host adapter. Consumers need no MoonBit
// installation. Compilation here is package construction, never runtime work.
const build = fileURLToPath(new URL("./_build/", import.meta.url));
execFileSync("moon", ["build", "--target", "js", "--release", "--target-dir", build,
  fileURLToPath(new URL("./bridge", import.meta.url))], {stdio: "inherit"});
await mkdir(new URL("./dist/", import.meta.url), {recursive: true});
await copyFile(`${build}/js/release/build/finos/morphir-host/embedding/bridge/bridge.js`,
  new URL("./dist/bridge.mjs", import.meta.url));
await copyFile(new URL("./bridge.d.mts", import.meta.url), new URL("./dist/bridge.d.mts", import.meta.url));
await copyFile(new URL("../../../LICENSE", import.meta.url), new URL("./dist/LICENSE-APACHE-2.0.txt", import.meta.url));

await checkedBuild({entrypoints: [fileURLToPath(new URL("./browser-worker.mts", import.meta.url))],
  outdir: fileURLToPath(new URL("./dist/", import.meta.url)),
  // The upstream compiler's optional Node filesystem backend requires constants.
  // Leave that backend external; browser compilation uses its in-memory backend.
  external: ["constants"], target: "browser", format: "esm", minify: true,
  plugins: [{name: "isolated-compiler", setup(build) {
    build.onResolve({filter: /^morphir:compiler-factory$/}, () => ({path: "compiler", namespace: "isolated"}));
    build.onLoad({filter: /.*/, namespace: "isolated"}, () => ({contents:
      `export function createCompiler() { const module = {exports:{}}; const exports = module.exports; ${source}\nreturn module.exports; }`,
      loader: "js"}));
  }}]});

await import("../../../tools/build-runtimes.ts");
// Portable qualification helper uses the same source in Node and Chromium.
await checkedBuild({entrypoints:[fileURLToPath(new URL('./test/saved-byte-preflight.mts',import.meta.url))],
  outdir:fileURLToPath(new URL('./dist/test/',import.meta.url)),target:'browser',format:'esm',naming:'[name].mjs'});
execFileSync(process.execPath, ["run", "tsc", "-p", fileURLToPath(new URL("./tsconfig.types.json", import.meta.url))], {
  cwd: fileURLToPath(new URL("../../../", import.meta.url)), stdio: "inherit",
});
