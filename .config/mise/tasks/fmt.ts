#!/usr/bin/env bun
// #MISE description="Format Go code"
// #MISE alias="f"

import { $ } from "bun";

async function main() {
  console.log("Formatting Go code...");
  await $`go fmt ./...`;
  console.log("Formatting complete");
}

main().catch((err) => {
  console.error("Format failed:", err.message);
  process.exit(1);
});
