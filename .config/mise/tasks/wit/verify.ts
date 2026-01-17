#!/usr/bin/env bun
// #MISE description="Verify WIT files using wasm-tools"
// #MISE alias="wv"

import { $, Glob } from "bun";
import { readdirSync, statSync } from "fs";
import { join } from "path";

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

async function countWitFiles(dir: string): Promise<number> {
  const glob = new Glob("**/*.wit");
  let count = 0;
  for await (const _ of glob.scan({ cwd: dir, onlyFiles: true })) {
    count++;
  }
  return count;
}

function getPackageDirs(witDir: string): string[] {
  try {
    return readdirSync(witDir)
      .filter((f) => {
        const path = join(witDir, f);
        return statSync(path).isDirectory();
      })
      .map((f) => join(witDir, f));
  } catch {
    return [];
  }
}

interface VerifyResult {
  package: string;
  valid: boolean;
  error?: string;
  fileCount: number;
}

async function verifyPackage(pkgDir: string): Promise<VerifyResult> {
  const pkgName = pkgDir.split("/").pop() || pkgDir;
  const fileCount = await countWitFiles(pkgDir);

  try {
    await $`wasm-tools component wit ${pkgDir} --all-features`.quiet();
    return { package: pkgName, valid: true, fileCount };
  } catch (err: unknown) {
    const error = err as Error & { stderr?: Buffer | string };
    let errorMsg = "";
    if (error.stderr) {
      errorMsg = Buffer.isBuffer(error.stderr)
        ? error.stderr.toString()
        : error.stderr;
    } else {
      errorMsg = error.message;
    }
    return { package: pkgName, valid: false, error: errorMsg.trim(), fileCount };
  }
}

async function main() {
  console.log("Verifying WIT files with wasm-tools...\n");

  // Check if wasm-tools is available
  if (!(await checkWasmTools())) {
    await installWasmTools();
  }

  const witDir = "wit";
  const packageDirs = getPackageDirs(witDir);

  if (packageDirs.length === 0) {
    console.log("No WIT packages found in wit/");
    return;
  }

  // Verify each package
  const results: VerifyResult[] = [];
  for (const pkgDir of packageDirs) {
    const result = await verifyPackage(pkgDir);
    results.push(result);
  }

  // Report results
  const valid = results.filter((r) => r.valid);
  const invalid = results.filter((r) => !r.valid);
  const totalFiles = results.reduce((sum, r) => sum + r.fileCount, 0);

  console.log(`Found ${totalFiles} WIT files across ${results.length} packages\n`);

  if (valid.length > 0) {
    console.log("Valid packages:");
    for (const r of valid) {
      console.log(`  [OK] ${r.package} (${r.fileCount} files)`);
    }
    console.log();
  }

  if (invalid.length > 0) {
    console.log("Invalid packages:");
    for (const r of invalid) {
      console.log(`  [FAIL] ${r.package} (${r.fileCount} files)`);
      // Show first line of error for brevity
      const firstLine = r.error?.split("\n").find((l) => l.includes("Caused by") || l.startsWith("error:")) || r.error?.split("\n")[0];
      if (firstLine) {
        console.log(`         ${firstLine}`);
      }
    }
    console.log();
  }

  // Summary
  console.log(`Summary: ${valid.length}/${results.length} packages valid`);

  if (invalid.length > 0) {
    console.log("\nNote: Some packages may fail due to WIT limitations:");
    console.log("  - Recursive types (e.g., AST nodes) not supported in WIT");
    console.log("  - Cross-package imports require specific syntax");
    console.log("\nRun with --verbose for full error details.");
    process.exit(1);
  }

  console.log("\nAll WIT packages validated successfully!");
}

main().catch((err) => {
  console.error("WIT verification failed:", err.message);
  process.exit(1);
});
