#!/usr/bin/env bun
// #MISE description="Verify all modules build successfully"
// #MISE alias="v"
// #MISE depends=["workspace:setup"]

import { $, Glob } from "bun";
import { existsSync, copyFileSync } from "fs";
import { dirname } from "path";

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

  // Ensure workspace is set up
  if (!existsSync("go.work")) {
    console.log("Setting up Go workspace...");
    await $`go work init`;
    const modules = await findGoModules();
    for (const mod of modules) {
      await $`go work use ${mod}`;
    }
  }

  console.log("Verifying all modules build...");

  // Find all Go modules
  const modules = await findGoModules();

  let failed = false;
  for (const dir of modules) {
    if (!existsSync(dir)) continue;

    console.log(`Building ${dir}...`);
    try {
      await $`go build ./...`.cwd(dir);
    } catch (err) {
      console.error(`Build failed in ${dir}`);
      failed = true;
    }
  }

  if (failed) {
    console.error("Some modules failed to build.");
    process.exit(1);
  }

  console.log("All modules build successfully!");
}

main().catch((err) => {
  console.error("Verify failed:", err.message);
  process.exit(1);
});
