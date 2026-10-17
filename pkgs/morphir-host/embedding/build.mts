import { execFileSync } from "node:child_process";
import {checkedBuild} from "../../../tools/build.ts";
import {fileURLToPath} from "node:url";
import {readFile} from "node:fs/promises";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const compilerPath = require.resolve("@moonbit/moonc-worker");
const source = await readFile(compilerPath, "utf8");

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
execFileSync(process.execPath, ["run", "tsc", "-p", fileURLToPath(new URL("./tsconfig.types.json", import.meta.url))], {
  cwd: fileURLToPath(new URL("../../../", import.meta.url)), stdio: "inherit",
});
