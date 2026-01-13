#!/usr/bin/env bun
// #MISE description="Run tests"
// #MISE alias="t"
// #MISE depends=["workspace:doctor"]
// #USAGE flag "-v --verbose" help="Enable verbose test output"

import { $, Glob } from "bun";
import { existsSync, copyFileSync } from "fs";
import { parseArgs } from "util";
import { dirname } from "path";

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    verbose: { type: "boolean", short: "v", default: false },
  },
  strict: true,
  allowPositionals: true,
});

async function syncChangelog() {
  const src = "CHANGELOG.md";
  const dest = "cmd/morphir/cmd/CHANGELOG.md";

  if (existsSync(src)) {
    copyFileSync(src, dest);
  }
}

async function findGoModules(): Promise<string[]> {
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    if (!file.includes("node_modules/") && !file.includes("vendor/")) {
      modFiles.push(file);
    }
  }
  return modFiles.map((f) => dirname(f)).filter((d) => d !== ".");
}

async function main() {
  // Sync changelog first (required for go:embed)
  await syncChangelog();

  console.log("Running tests...");

  // Find all Go modules
  const modules = await findGoModules();

  // Filter to modules that likely have tests
  const testableModules = modules.filter(
    (m) =>
      m.startsWith("cmd/") ||
      (m.startsWith("pkg/") && !m.includes("tests/"))
  );

  const verboseFlag = values.verbose ? "-v" : "";
  let failed = false;

  for (const dir of testableModules) {
    if (!existsSync(dir)) continue;

    console.log(`Testing ${dir}...`);
    try {
      if (values.verbose) {
        await $`go test -v ./...`.cwd(dir);
      } else {
        await $`go test ./...`.cwd(dir);
      }
    } catch (err) {
      console.error(`Tests failed in ${dir}`);
      failed = true;
    }
  }

  if (failed) {
    console.error("Some tests failed.");
    process.exit(1);
  }

  console.log("All tests passed");
}

main().catch((err) => {
  console.error("Test failed:", err.message);
  process.exit(1);
});
