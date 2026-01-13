#!/usr/bin/env bun
// #MISE description="Test that cmd/morphir builds without go.work (external consumption)"

import { $ } from "bun";
import { existsSync, renameSync, copyFileSync } from "fs";

async function main() {
  console.log("Testing external consumption (building without go.work)...");

  // Backup go.work if it exists
  const goWorkExists = existsSync("go.work");
  if (goWorkExists) {
    renameSync("go.work", "go.work.backup");
    if (existsSync("go.work.sum")) {
      renameSync("go.work.sum", "go.work.sum.backup");
    }
  }

  // Sync CHANGELOG
  if (existsSync("CHANGELOG.md")) {
    copyFileSync("CHANGELOG.md", "cmd/morphir/cmd/CHANGELOG.md");
  }

  let success = false;
  try {
    console.log("Building cmd/morphir without workspace...");
    await $`GONOSUMDB=github.com/finos/morphir/* go build -C cmd/morphir ./...`;
    console.log("External consumption test passed!");
    success = true;
  } catch (err: any) {
    console.error("External consumption test failed:", err.stderr || err.message);
  } finally {
    // Restore go.work
    if (goWorkExists) {
      renameSync("go.work.backup", "go.work");
      if (existsSync("go.work.sum.backup")) {
        renameSync("go.work.sum.backup", "go.work.sum");
      }
    }
  }

  if (!success) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Test failed:", err.message);
  process.exit(1);
});
