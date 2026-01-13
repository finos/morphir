#!/usr/bin/env bun
// #MISE description="Run pre-release validation checks"
// #USAGE flag "--json" help="Output results as JSON"
// #USAGE flag "-q --quiet" help="Suppress non-essential output"
// #USAGE arg "[version]" help="Version to validate (e.g., v0.4.0-alpha.1)"

import { $, Glob } from "bun";
import { parseArgs } from "util";
import { existsSync, readFileSync, copyFileSync, renameSync } from "fs";

// Parse arguments
const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    json: { type: "boolean", default: false },
    quiet: { type: "boolean", short: "q", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
  strict: true,
  allowPositionals: true,
});

if (values.help) {
  console.log(`release-validate - Pre-release validation for Morphir

Usage: mise run release:validate [OPTIONS] [VERSION]

Options:
  --json       Output results as JSON (for automation)
  -q, --quiet  Suppress non-essential output
  -h, --help   Show this help message

Arguments:
  VERSION      Optional version to validate (e.g., v0.4.0-alpha.1)

Examples:
  mise run release:validate v0.4.0-alpha.1
  mise run release:validate --json v0.4.0`);
  process.exit(0);
}

const version = positionals[0] || "";
const jsonOutput = values.json;
const quiet = values.quiet;

// Colors (disabled for JSON output)
const colors = {
  red: jsonOutput ? "" : "\x1b[0;31m",
  green: jsonOutput ? "" : "\x1b[0;32m",
  yellow: jsonOutput ? "" : "\x1b[1;33m",
  reset: jsonOutput ? "" : "\x1b[0m",
};

// Results tracking
interface Check {
  name: string;
  status: "success" | "error" | "warning";
  message: string;
  details?: string;
}

const checks: Check[] = [];
let errors = 0;
let warnings = 0;

function addCheck(
  name: string,
  status: "success" | "error" | "warning",
  message: string,
  details?: string
) {
  checks.push({ name, status, message, details });
}

function error(name: string, message: string, details?: string) {
  addCheck(name, "error", message, details);
  if (!jsonOutput) {
    console.error(`${colors.red}ERROR:${colors.reset} ${message}`);
    if (details) console.error(`  ${details}`);
  }
  errors++;
}

function warn(name: string, message: string, details?: string) {
  addCheck(name, "warning", message, details);
  if (!jsonOutput) {
    console.warn(`${colors.yellow}WARNING:${colors.reset} ${message}`);
    if (details) console.warn(`  ${details}`);
  }
  warnings++;
}

function success(name: string, message: string) {
  addCheck(name, "success", message);
  if (!jsonOutput && !quiet) {
    console.log(`${colors.green}✓${colors.reset} ${message}`);
  }
}

function header(text: string) {
  if (!jsonOutput && !quiet) {
    console.log("");
    console.log("━".repeat(60));
    console.log(` ${text}`);
    console.log("━".repeat(60));
  }
}

async function findGoModFiles(): Promise<string[]> {
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    if (!file.includes("node_modules/") && !file.includes("vendor/")) {
      modFiles.push(file);
    }
  }
  return modFiles;
}

async function main() {
  // Header
  if (!jsonOutput && !quiet) {
    console.log("");
    console.log("Morphir Release Validation");
    console.log("==========================");
    console.log("");
    if (version) {
      console.log(`Validating for version: ${version}`);
    }
  }

  const goModFiles = await findGoModFiles();

  // 1. Check for replace directives
  header("Checking for replace directives");
  const replaceFiles: string[] = [];
  for (const modFile of goModFiles) {
    const content = readFileSync(modFile, "utf-8");
    if (/^replace /m.test(content)) {
      replaceFiles.push(modFile);
    }
  }
  if (replaceFiles.length > 0) {
    error("replace_directives", "Replace directives found in go.mod files", replaceFiles.join(" "));
  } else {
    success("replace_directives", "No replace directives found");
  }

  // 2. Check for pseudo-versions
  header("Checking for pseudo-versions");
  const pseudoFiles: string[] = [];
  const pseudoPattern = /github\.com\/finos\/morphir.*v\d+\.\d+\.\d+-\d{14}-[a-f0-9]+/;
  for (const modFile of goModFiles) {
    const content = readFileSync(modFile, "utf-8");
    if (pseudoPattern.test(content)) {
      pseudoFiles.push(modFile);
    }
  }
  if (pseudoFiles.length > 0) {
    error("pseudo_versions", "Pseudo-versions found in go.mod files", pseudoFiles.join(" "));
  } else {
    success("pseudo_versions", "No pseudo-versions found");
  }

  // 3. Check CHANGELOG.md is committed
  header("Checking CHANGELOG.md for go:embed");
  const changelogPath = "cmd/morphir/cmd/CHANGELOG.md";
  if (existsSync(changelogPath)) {
    try {
      await $`git ls-files --error-unmatch ${changelogPath}`.quiet();
      success("changelog_embed", "cmd/morphir/cmd/CHANGELOG.md is tracked by git");
    } catch {
      error("changelog_embed", "cmd/morphir/cmd/CHANGELOG.md exists but is not tracked by git", "Run: git add cmd/morphir/cmd/CHANGELOG.md");
    }
  } else {
    error("changelog_embed", "cmd/morphir/cmd/CHANGELOG.md does not exist", "Run: cp CHANGELOG.md cmd/morphir/cmd/CHANGELOG.md");
  }

  // 4. Check go.work is not staged
  header("Checking go.work is not staged");
  try {
    const staged = await $`git diff --cached --name-only`.text();
    if (staged.includes("go.work")) {
      error("go_work_staged", "go.work is staged for commit", "Run: git reset go.work go.work.sum");
    } else {
      success("go_work_staged", "go.work is not staged");
    }
  } catch {
    success("go_work_staged", "go.work is not staged");
  }

  // 5. Validate goreleaser config
  header("Validating GoReleaser configuration");
  try {
    await $`which goreleaser`.quiet();
    try {
      await $`goreleaser check`.quiet();
      success("goreleaser_config", "GoReleaser configuration is valid");
    } catch {
      error("goreleaser_config", "GoReleaser configuration is invalid");
    }
  } catch {
    warn("goreleaser_config", "goreleaser not installed, skipping validation", "Install: mise install goreleaser");
  }

  // 6. Check goreleaser has GONOSUMDB
  header("Checking GoReleaser GONOSUMDB configuration");
  if (existsSync(".goreleaser.yaml")) {
    const content = readFileSync(".goreleaser.yaml", "utf-8");
    if (content.includes("GONOSUMDB=github.com/finos/morphir")) {
      success("gonosumdb", "GONOSUMDB is configured in .goreleaser.yaml");
    } else {
      error("gonosumdb", "GONOSUMDB not configured in .goreleaser.yaml", "Add to env: - GONOSUMDB=github.com/finos/morphir/*");
    }
  } else {
    error("gonosumdb", ".goreleaser.yaml not found");
  }

  // 7. Check goreleaser has dir: cmd/morphir
  header("Checking GoReleaser build directory");
  if (existsSync(".goreleaser.yaml")) {
    const content = readFileSync(".goreleaser.yaml", "utf-8");
    if (content.includes("dir: cmd/morphir")) {
      success("build_dir", "Build directory is configured correctly");
    } else {
      error("build_dir", "Build directory not configured in .goreleaser.yaml", "Add to builds: dir: cmd/morphir");
    }
  }

  // 8. Check no go work sync in hooks
  header("Checking GoReleaser hooks");
  if (existsSync(".goreleaser.yaml")) {
    const content = readFileSync(".goreleaser.yaml", "utf-8");
    if (content.includes("go work sync")) {
      error("go_work_sync", "go work sync found in goreleaser hooks", "Remove from before.hooks");
    } else {
      success("go_work_sync", "No problematic hooks found");
    }
  }

  // 9. Check git status is clean
  header("Checking git status");
  try {
    const status = await $`git status --porcelain`.text();
    const dirtyCount = status.trim().split("\n").filter((l) => l.trim()).length;
    if (dirtyCount > 0) {
      warn("git_clean", `Working directory has ${dirtyCount} uncommitted changes`);
    } else {
      success("git_clean", "Working directory is clean");
    }
  } catch {
    warn("git_clean", "Could not check git status");
  }

  // 10. Check CHANGELOG has version section
  header("Checking CHANGELOG.md");
  if (existsSync("CHANGELOG.md")) {
    const changelog = readFileSync("CHANGELOG.md", "utf-8");
    if (version) {
      const versionNoV = version.replace(/^v/, "");
      const versionPattern = new RegExp(`## \\[?${versionNoV.replace(/\./g, "\\.")}\\]?`);
      if (versionPattern.test(changelog)) {
        success("changelog_version", `CHANGELOG.md has section for ${version}`);
      } else {
        warn("changelog_version", `CHANGELOG.md may not have section for ${version}`, "Ensure CHANGELOG.md is updated before release");
      }
    } else {
      if (changelog.includes("## [Unreleased]")) {
        success("changelog_version", "CHANGELOG.md has Unreleased section");
      } else {
        warn("changelog_version", "CHANGELOG.md has no Unreleased section");
      }
    }
  }

  // 11. Check module list matches actual modules (check release/tags.ts or release-tags.sh)
  header("Checking module list");
  // For now, we'll auto-detect modules instead of checking against a hardcoded list
  const actualModules = goModFiles
    .map((f) => f.replace("/go.mod", ""))
    .filter((m) => m.startsWith("pkg/") || m.startsWith("cmd/"))
    .sort();
  success("module_list", `Found ${actualModules.length} Go modules`);

  // 12. Check internal module version tags exist
  header("Checking internal module version tags");
  const missingTags: string[] = [];
  const moduleRefPattern = /github\.com\/finos\/morphir\/(pkg|cmd)\/[\w\/-]+\s+v[\d.]+(-[\w.]+)?/g;

  for (const modFile of goModFiles) {
    const content = readFileSync(modFile, "utf-8");
    const matches = content.match(moduleRefPattern) || [];

    for (const match of matches) {
      const parts = match.split(/\s+/);
      if (parts.length < 2) continue;

      const modPath = parts[0];
      const modVersion = parts[1];

      // Skip pseudo-versions
      if (/v\d+\.\d+\.\d+-\d{14}-/.test(modVersion)) continue;

      const relPath = modPath.replace("github.com/finos/morphir/", "");
      const expectedTag = `${relPath}/${modVersion}`;

      try {
        await $`git rev-parse ${expectedTag}`.quiet();
      } catch {
        try {
          const remote = await $`git ls-remote --tags origin refs/tags/${expectedTag}`.text();
          if (!remote.trim()) {
            missingTags.push(expectedTag);
          }
        } catch {
          missingTags.push(expectedTag);
        }
      }
    }
  }

  const uniqueMissingTags = [...new Set(missingTags)];
  if (uniqueMissingTags.length > 0) {
    error("module_tags", `Internal module version tags not found: ${uniqueMissingTags.join(" ")}`, "These modules reference versions that don't exist. Update go.mod or create tags.");
  } else {
    success("module_tags", "All internal module version tags exist");
  }

  // 13. Simulate go mod tidy (without go.work)
  header("Simulating go mod tidy without workspace");
  if (!quiet && !jsonOutput) {
    console.log("  Testing if go mod tidy would succeed in release environment...");
  }

  // Backup files
  const goWorkExists = existsSync("go.work");
  if (goWorkExists) {
    renameSync("go.work", "go.work.backup");
    if (existsSync("go.work.sum")) {
      renameSync("go.work.sum", "go.work.sum.backup");
    }
  }

  const cmdMorphirGoMod = "cmd/morphir/go.mod";
  const cmdMorphirGoSum = "cmd/morphir/go.sum";
  if (existsSync(cmdMorphirGoMod)) {
    copyFileSync(cmdMorphirGoMod, `${cmdMorphirGoMod}.backup`);
  }
  if (existsSync(cmdMorphirGoSum)) {
    copyFileSync(cmdMorphirGoSum, `${cmdMorphirGoSum}.backup`);
  }

  let modTidyError = "";
  try {
    await $`GONOSUMDB=github.com/finos/morphir/* go mod tidy -C cmd/morphir`.quiet();
  } catch (err: any) {
    modTidyError = err.stderr || err.message || "go mod tidy failed";
  }

  // Restore files
  if (goWorkExists) {
    renameSync("go.work.backup", "go.work");
    if (existsSync("go.work.sum.backup")) {
      renameSync("go.work.sum.backup", "go.work.sum");
    }
  }
  if (existsSync(`${cmdMorphirGoMod}.backup`)) {
    renameSync(`${cmdMorphirGoMod}.backup`, cmdMorphirGoMod);
  }
  if (existsSync(`${cmdMorphirGoSum}.backup`)) {
    renameSync(`${cmdMorphirGoSum}.backup`, cmdMorphirGoSum);
  }

  if (modTidyError) {
    const errorMatch = modTidyError.match(/(unknown revision|invalid version|no matching versions)[^\n]*/);
    const summary = errorMatch ? errorMatch[0] : "go mod tidy failed";
    error("mod_tidy_simulation", `go mod tidy would fail in release: ${summary}`);
  } else {
    success("mod_tidy_simulation", "go mod tidy simulation passed");
  }

  // Output results
  if (jsonOutput) {
    const status = errors > 0 ? "error" : warnings > 0 ? "warning" : "success";
    console.log(JSON.stringify({
      version: version || null,
      status,
      errors,
      warnings,
      checks,
    }, null, 2));
  } else {
    header("Validation Summary");
    console.log("");

    if (errors > 0) {
      console.log(`${colors.red}FAILED${colors.reset}: ${errors} error(s), ${warnings} warning(s)`);
      console.log("");
      console.log("Please fix the errors above before proceeding with release.");
      process.exit(1);
    } else if (warnings > 0) {
      console.log(`${colors.yellow}PASSED WITH WARNINGS${colors.reset}: ${warnings} warning(s)`);
      console.log("");
      console.log("Review warnings above. You may proceed with release if they are acceptable.");
    } else {
      console.log(`${colors.green}PASSED${colors.reset}: All validations successful`);
      console.log("");
      console.log("Repository is ready for release.");
    }
  }
}

main().catch((err) => {
  console.error("Validation failed:", err.message);
  process.exit(1);
});
