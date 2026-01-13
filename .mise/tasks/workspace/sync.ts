#!/usr/bin/env bun
// #MISE description="Sync workspace dependencies"

import { $ } from "bun";
import { existsSync } from "fs";

async function main() {
  if (!existsSync("go.work")) {
    console.error("Error: go.work not found. Run 'mise run workspace:setup' first.");
    process.exit(1);
  }

  console.log("Syncing Go workspace...");
  await $`go work sync`;
  console.log("Workspace sync complete");
}

main().catch((err) => {
  console.error("Workspace sync failed:", err.message);
  process.exit(1);
});
