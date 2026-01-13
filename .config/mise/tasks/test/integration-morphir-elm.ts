#!/usr/bin/env bun
// #MISE description="Run morphir-elm toolchain integration tests"

import { $ } from "bun";

async function main() {
  console.log("Running morphir-elm integration tests...");
  await $`go test -v -run 'TestIntegration_MorphirElmMake' ./pkg/toolchain/`;
  console.log("morphir-elm integration tests passed");
}

main().catch((err) => {
  console.error("Integration tests failed:", err.message);
  process.exit(1);
});
