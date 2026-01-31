/**
 * Bundles the validation worker with Ajv into a single static file.
 * Uses npx esbuild so no need to add esbuild to package.json.
 * Run: npm run build:worker
 */
const { execSync } = require("child_process");
const path = require("path");

const scriptDir = __dirname;
const root = path.resolve(scriptDir, "..");
const entry = path.join(scriptDir, "validation-inline-worker-src.mjs");
const outfile = path.join(root, "static", "validation-inline.worker.js");

execSync(
  `npx --yes esbuild "${entry}" --bundle --format=iife --platform=browser --target=es2020 --outfile="${outfile}" --minify`,
  { stdio: "inherit", cwd: root }
);
console.log("Built static/validation-inline.worker.js");
