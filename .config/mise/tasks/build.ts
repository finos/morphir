#!/usr/bin/env bun
// #MISE description="Build the morphir CLI"
// #MISE alias="b"

import { $ } from "bun";
import { existsSync, mkdirSync } from "fs";

const binDir = "bin";
const output = process.platform === "win32" ? "bin/morphir.exe" : "bin/morphir";

async function main() {
  // Ensure bin directory exists
  if (!existsSync(binDir)) {
    mkdirSync(binDir, { recursive: true });
  }

  console.log("Building morphir CLI...");
  await $`go build -o ${output} ./cmd/morphir`;
  console.log(`Built: ${output}`);
}

main().catch((err) => {
  console.error("Build failed:", err.message);
  process.exit(1);
});
