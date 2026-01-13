#!/usr/bin/env bun
// #MISE description="Run all integration tests"

import { $ } from "bun";
import { existsSync } from "fs";

const integrationDirs = [
  "pkg/toolchain",
  "pkg/bindings/morphir-elm",
];

async function main() {
  console.log("Running integration tests...");

  let failed = false;

  for (const dir of integrationDirs) {
    if (!existsSync(dir)) {
      console.log(`Skipping ${dir} (not found)`);
      continue;
    }

    console.log(`Running integration tests in ${dir}...`);
    try {
      await $`go test -v -run 'TestIntegration' ./${dir}/...`;
    } catch (err) {
      console.error(`Integration tests failed in ${dir}`);
      failed = true;
    }
  }

  if (failed) {
    console.error("Some integration tests failed.");
    process.exit(1);
  }

  console.log("All integration tests passed");
}

main().catch((err) => {
  console.error("Integration tests failed:", err.message);
  process.exit(1);
});
