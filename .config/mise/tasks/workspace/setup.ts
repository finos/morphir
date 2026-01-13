#!/usr/bin/env bun
// #MISE description="Set up Go workspace with all modules"

import { $, Glob } from "bun";
import { existsSync } from "fs";
import { dirname } from "path";

async function findGoModules(): Promise<string[]> {
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    if (!file.includes("node_modules/") && !file.includes("vendor/")) {
      modFiles.push(file);
    }
  }
  return modFiles.map((f) => dirname(f)).filter((d) => d !== ".").sort();
}

async function main() {
  console.log("Setting up Go workspace...");

  // Find all Go modules
  const modules = await findGoModules();
  console.log(`Found ${modules.length} Go modules`);

  // Check if go.work exists
  if (existsSync("go.work")) {
    console.log("go.work already exists, updating...");
  } else {
    console.log("Creating go.work...");
    await $`go work init`;
  }

  // Add all modules to workspace
  for (const mod of modules) {
    console.log(`  Adding ${mod}`);
    try {
      await $`go work use ${mod}`.quiet();
    } catch {
      console.warn(`  Warning: Could not add ${mod}`);
    }
  }

  // Run go work sync
  console.log("Syncing workspace...");
  await $`go work sync`;

  console.log("");
  console.log("Workspace setup complete!");
  console.log(`  Modules: ${modules.length}`);
  console.log("  Run 'mise run workspace:doctor' to verify health");
}

main().catch((err) => {
  console.error("Workspace setup failed:", err.message);
  process.exit(1);
});
