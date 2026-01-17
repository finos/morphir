#!/usr/bin/env bun
// #MISE description="Verify WIT files using wasm-tools"
// #MISE alias="wv"

import { $, Glob } from "bun";

async function checkWasmTools(): Promise<boolean> {
  try {
    await $`which wasm-tools`.quiet();
    return true;
  } catch {
    return false;
  }
}

async function installWasmTools() {
  console.log("Installing wasm-tools via cargo...");
  await $`cargo install wasm-tools`;
}

async function countWitFiles(): Promise<number> {
  const glob = new Glob("**/*.wit");
  let count = 0;
  for await (const _ of glob.scan({ cwd: "wit", onlyFiles: true })) {
    count++;
  }
  return count;
}

async function main() {
  console.log("Verifying WIT files...");

  // Check if wasm-tools is available
  if (!(await checkWasmTools())) {
    await installWasmTools();
  }

  // Count WIT files for reporting
  const witCount = await countWitFiles();
  console.log(`Found ${witCount} WIT files in wit/`);

  // Run wasm-tools component wit to validate all WIT files
  // This validates syntax and cross-package dependencies
  try {
    const result = await $`wasm-tools component wit wit/ --all-features`.text();
    if (result.trim()) {
      console.log("Resolved WIT output:");
      console.log(result);
    }
    console.log(`All ${witCount} WIT files validated successfully!`);
  } catch (err: unknown) {
    const error = err as Error & { stderr?: Buffer | string; stdout?: Buffer | string };
    console.error("WIT validation failed:");
    if (error.stderr) {
      const stderrStr = Buffer.isBuffer(error.stderr)
        ? error.stderr.toString()
        : error.stderr;
      console.error(stderrStr);
    } else {
      console.error(error.message);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("WIT verification failed:", err.message);
  process.exit(1);
});
