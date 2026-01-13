#!/usr/bin/env bun
// #MISE description="Clean build artifacts"
// #MISE alias="c"

import { rmSync, existsSync } from "fs";

const artifacts = ["bin", "dist", "coverage"];

async function main() {
  for (const dir of artifacts) {
    if (existsSync(dir)) {
      console.log(`Removing ${dir}/...`);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  console.log("Clean complete");
}

main().catch((err) => {
  console.error("Clean failed:", err.message);
  process.exit(1);
});
