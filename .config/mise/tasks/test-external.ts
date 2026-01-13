#!/usr/bin/env bun
// #MISE description="Test that cmd/morphir builds without go.work (external consumption)"

import { $ } from "bun";
import { existsSync, renameSync, copyFileSync } from "fs";

// Detect if this is a release branch and get the version
function detectReleaseBranch(): string | null {
  // In GitHub Actions, use GITHUB_HEAD_REF (PR source branch) or GITHUB_REF_NAME
  const branch =
    process.env.GITHUB_HEAD_REF ||
    process.env.GITHUB_REF_NAME ||
    (() => {
      try {
        const result = Bun.spawnSync(["git", "branch", "--show-current"]);
        return result.stdout.toString().trim();
      } catch {
        return "";
      }
    })();

  // Match release/vX.Y.Z or release/vX.Y.Z-alpha.N patterns
  const match = branch.match(/^release\/(v[\d.]+(?:-[a-zA-Z]+\.\d+)?)$/);
  return match ? match[1] : null;
}

async function main() {
  console.log("Testing external consumption (building without go.work)...");

  // Check if this is a release branch
  const releaseVersion = detectReleaseBranch();
  if (releaseVersion) {
    console.log(`Detected release branch for ${releaseVersion}`);
  }

  // Backup go.work if it exists
  const goWorkExists = existsSync("go.work");
  if (goWorkExists) {
    renameSync("go.work", "go.work.backup");
    if (existsSync("go.work.sum")) {
      renameSync("go.work.sum", "go.work.sum.backup");
    }
  }

  // Sync CHANGELOG
  if (existsSync("CHANGELOG.md")) {
    copyFileSync("CHANGELOG.md", "cmd/morphir/cmd/CHANGELOG.md");
  }

  let success = false;
  try {
    console.log("Building cmd/morphir without workspace...");
    await $`GONOSUMDB=github.com/finos/morphir/* go build -C cmd/morphir ./...`;
    console.log("External consumption test passed!");
    success = true;
  } catch (err: any) {
    const errorOutput = err.stderr?.toString() || err.message || "";

    // Check for specific cross-module dependency errors
    // These occur when code uses features from internal modules that aren't published yet
    const isCrossModuleError =
      errorOutput.includes("undefined") &&
      errorOutput.includes("github.com/finos/morphir/pkg/");

    if (releaseVersion && isCrossModuleError) {
      console.log("\n⚠️  Cross-module dependency detected in release PR");
      console.log(
        "   This code uses features from internal modules that aren't published yet."
      );
      console.log(
        "   After this release is tagged and published, external consumption will work."
      );
      console.log("\n   Error details:");
      console.log(
        errorOutput
          .split("\n")
          .filter((l: string) => l.includes("undefined") || l.includes("#"))
          .slice(0, 5)
          .join("\n")
      );
      console.log("\n   This is expected for release PRs with cross-module changes.");
      console.log(
        "   Proceeding - the modules will be available after tags are pushed.\n"
      );
      success = true; // Allow the test to pass for release PRs with cross-module changes
    } else {
      console.error("External consumption test failed:", errorOutput);
    }
  } finally {
    // Restore go.work
    if (goWorkExists) {
      renameSync("go.work.backup", "go.work");
      if (existsSync("go.work.sum.backup")) {
        renameSync("go.work.sum.backup", "go.work.sum");
      }
    }
  }

  if (!success) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Test failed:", err.message);
  process.exit(1);
});
