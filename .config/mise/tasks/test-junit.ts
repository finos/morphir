#!/usr/bin/env bun
// #MISE description="Run tests with JUnit XML output"
// #MISE depends=["workspace:setup"]

import { $, Glob } from "bun";
import { existsSync, mkdirSync, copyFileSync } from "fs";
import { dirname } from "path";

async function syncChangelog() {
  const src = "CHANGELOG.md";
  const dest = "cmd/morphir/cmd/CHANGELOG.md";
  if (existsSync(src)) {
    copyFileSync(src, dest);
  }
}

async function findGoModules(): Promise<string[]> {
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    if (!file.includes("node_modules/") && !file.includes("vendor/")) {
      modFiles.push(file);
    }
  }
  return modFiles.map((f) => dirname(f)).filter((d) => d !== ".");
}

async function main() {
  await syncChangelog();

  // Ensure output directory exists
  if (!existsSync("test-results")) {
    mkdirSync("test-results", { recursive: true });
  }

  console.log("Running tests with JUnit output...");

  const modules = await findGoModules();
  const testableModules = modules.filter(
    (m) => m.startsWith("cmd/") || (m.startsWith("pkg/") && !m.includes("tests/"))
  );

  let failed = false;

  for (const dir of testableModules) {
    if (!existsSync(dir)) continue;

    const safeName = dir.replace(/\//g, "-");
    console.log(`Testing ${dir}...`);

    try {
      // Run tests with coverage and save results
      await $`go test -v -coverprofile=coverage-${safeName}.out -json ./... 2>&1 | tee test-results/${safeName}.json`.cwd(dir);
    } catch (err) {
      console.error(`Tests failed in ${dir}`);
      failed = true;
    }
  }

  // Merge coverage files
  const coverageGlob = new Glob("coverage-*.out");
  const coverageFiles: string[] = [];
  for await (const file of coverageGlob.scan({ cwd: ".", onlyFiles: true })) {
    coverageFiles.push(file);
  }
  if (coverageFiles.length > 0) {
    console.log("Merging coverage files...");
    // Simple merge - concatenate coverage files
    await $`cat ${coverageFiles} > coverage.out`;
  }

  if (failed) {
    console.error("Some tests failed.");
    process.exit(1);
  }

  console.log("All tests passed");
}

main().catch((err) => {
  console.error("Test failed:", err.message);
  process.exit(1);
});
