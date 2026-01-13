#!/usr/bin/env bun
// #MISE description="Run all BDD tests"

import { $ } from "bun";

async function main() {
  console.log("Running BDD tests...");
  await $`go test -v -run 'TestFeatures' ./tests/bdd/`;
  console.log("BDD tests passed");
}

main().catch((err) => {
  console.error("BDD tests failed:", err.message);
  process.exit(1);
});
