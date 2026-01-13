#!/usr/bin/env bun
// #MISE description="Build a local snapshot release (for testing)"

import { $ } from "bun";

async function main() {
  console.log("Building snapshot release...");
  await $`goreleaser release --snapshot --clean`;
  console.log("Snapshot build complete. Check dist/ for artifacts.");
}

main().catch((err) => {
  console.error("Snapshot build failed:", err.message);
  process.exit(1);
});
