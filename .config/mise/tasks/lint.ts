#!/usr/bin/env bun
// #MISE description="Run linters on Go code"
// #MISE alias="l"

import { $, Glob } from "bun";
import { copyFileSync, existsSync } from "fs";
import { dirname } from "path";

// Modules to lint (those with Go code)
const modules = [
  "cmd/morphir",
  "pkg/bindings/golang",
  "pkg/bindings/morphir-elm",
  "pkg/bindings/typemap",
  "pkg/bindings/wit",
  "pkg/config",
  "pkg/docling-doc",
  "pkg/logging",
  "pkg/models",
  "pkg/nbformat",
  "pkg/pipeline",
  "pkg/sdk",
  "pkg/task",
  "pkg/toolchain",
  "pkg/tooling",
  "pkg/vfs",
];

async function syncChangelog() {
  const src = "CHANGELOG.md";
  const dest = "cmd/morphir/cmd/CHANGELOG.md";

  if (existsSync(src)) {
    copyFileSync(src, dest);
    console.log("Synced CHANGELOG.md to cmd/morphir/cmd/");
  }
}

async function findGoModules(): Promise<string[]> {
  // Find all directories with go.mod files
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    // Skip node_modules, vendor, and tests directories
    if (
      !file.includes("node_modules/") &&
      !file.includes("vendor/") &&
      !file.includes("tests/")
    ) {
      modFiles.push(file);
    }
  }
  return modFiles.map((f) => dirname(f)).filter((d) => d !== ".");
}

async function main() {
  // Sync changelog first (required for go:embed)
  await syncChangelog();

  // Check if golangci-lint is available
  try {
    await $`which golangci-lint`.quiet();
  } catch {
    console.error(
      "golangci-lint not found. Install with: mise install golangci-lint"
    );
    process.exit(1);
  }

  console.log("Running linters...");

  // Find all modules dynamically
  const allModules = await findGoModules();
  const modulesToLint = modules.filter((m) => allModules.includes(m));

  let failed = false;
  for (const dir of modulesToLint) {
    if (!existsSync(dir)) continue;

    console.log(`Linting ${dir}...`);
    try {
      await $`golangci-lint run --timeout=5m`.cwd(dir);
    } catch (err) {
      console.error(`Lint failed in ${dir}`);
      failed = true;
    }
  }

  if (failed) {
    console.error("Linting failed.");
    process.exit(1);
  }

  console.log("Linting complete");
}

main().catch((err) => {
  console.error("Lint failed:", err.message);
  process.exit(1);
});
