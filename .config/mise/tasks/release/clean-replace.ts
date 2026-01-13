#!/usr/bin/env bun
// #MISE description="Remove replace directives from go.mod files for release"
// #MISE alias="crp"
// #USAGE flag "--dry-run" help="Show what would be done without making changes"
// #USAGE flag "--json" help="Output results as JSON"

import { Glob } from "bun";
import { readFileSync, writeFileSync } from "fs";
import { parseArgs } from "util";

// Parse arguments
const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    "dry-run": { type: "boolean", default: false },
    json: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
  strict: true,
  allowPositionals: false,
});

if (values.help) {
  console.log(`release:clean-replace - Remove replace directives from go.mod files

Usage: mise run release:clean-replace [OPTIONS]

Options:
  --dry-run    Show what would be done without making changes
  --json       Output results as JSON
  -h, --help   Show this help message

Description:
  This is a safeguard script for releases. We use go.work for local development,
  so replace directives should never be committed. This script ensures go install
  compatibility by removing any accidentally committed replace directives.

Examples:
  mise run release:clean-replace
  mise run release:clean-replace -- --dry-run
  mise run release:clean-replace -- --json`);
  process.exit(0);
}

const dryRun = values["dry-run"];
const jsonOutput = values.json;

// Colors (disabled for JSON output)
const colors = {
  red: jsonOutput ? "" : "\x1b[0;31m",
  green: jsonOutput ? "" : "\x1b[0;32m",
  yellow: jsonOutput ? "" : "\x1b[1;33m",
  blue: jsonOutput ? "" : "\x1b[0;34m",
  reset: jsonOutput ? "" : "\x1b[0m",
};

interface FileResult {
  path: string;
  hadReplace: boolean;
  modified: boolean;
  replaceCount: number;
}

interface Result {
  success: boolean;
  dryRun: boolean;
  filesChecked: number;
  filesModified: number;
  files: FileResult[];
  error?: string;
}

/**
 * Removes replace directives from go.mod files.
 *
 * This is a safeguard script for releases - we use go.work for local development,
 * so replace directives should never be committed. This script ensures go install
 * compatibility by removing any accidentally committed replace directives.
 */
async function main() {
  const result: Result = {
    success: true,
    dryRun,
    filesChecked: 0,
    filesModified: 0,
    files: [],
  };

  if (!jsonOutput) {
    if (dryRun) {
      console.log(`${colors.yellow}DRY RUN:${colors.reset} No changes will be made\n`);
    }
    console.log("Checking for replace directives in go.mod files...");
  }

  const glob = new Glob("**/go.mod");

  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    // Skip vendor and node_modules
    if (
      file.includes("node_modules/") ||
      file.includes("vendor/") ||
      file.includes(".git/")
    ) {
      continue;
    }

    result.filesChecked++;
    const content = readFileSync(file, "utf-8");

    // Count replace directives
    // Matches both single-line: replace foo => bar
    // And multi-line blocks: replace (\n...\n)
    const singleLineMatches = content.match(/^replace\s+.+$/gm) || [];
    const multiLineMatches = content.match(/^replace\s*\([^)]*\)/gm) || [];
    const replaceCount = singleLineMatches.length + multiLineMatches.length;
    const hasReplace = replaceCount > 0;

    const fileResult: FileResult = {
      path: file,
      hadReplace: hasReplace,
      modified: false,
      replaceCount,
    };

    if (hasReplace) {
      if (!jsonOutput) {
        console.log(
          `${colors.yellow}→${colors.reset} Found ${replaceCount} replace directive(s) in ${file}`
        );
      }

      if (!dryRun) {
        // Remove single-line replace directives
        let newContent = content.replace(/^replace\s+.+$/gm, "");

        // Remove multi-line replace blocks: replace (\n...\n)
        newContent = newContent.replace(/^replace\s*\([^)]*\)\s*$/gm, "");

        // Clean up multiple consecutive blank lines
        newContent = newContent.replace(/\n{3,}/g, "\n\n");

        writeFileSync(file, newContent);
        fileResult.modified = true;
        result.filesModified++;

        if (!jsonOutput) {
          console.log(`${colors.green}✓${colors.reset} Removed replace directives from ${file}`);
        }
      } else {
        if (!jsonOutput) {
          console.log(`${colors.blue}  Would remove ${replaceCount} replace directive(s)${colors.reset}`);
        }
      }
    }

    result.files.push(fileResult);
  }

  if (jsonOutput) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log("");
    if (dryRun) {
      const wouldModify = result.files.filter((f) => f.hadReplace).length;
      console.log(
        `${colors.yellow}DRY RUN:${colors.reset} Checked ${result.filesChecked} go.mod files, would modify ${wouldModify}`
      );
    } else {
      console.log(
        `${colors.green}✓${colors.reset} Checked ${result.filesChecked} go.mod files, modified ${result.filesModified}`
      );
    }
    console.log("Replace directive check complete.");
  }

  return result;
}

main().catch((err) => {
  if (jsonOutput) {
    console.log(
      JSON.stringify({
        success: false,
        dryRun,
        filesChecked: 0,
        filesModified: 0,
        files: [],
        error: err.message,
      })
    );
  } else {
    console.error(`${colors.red}ERROR:${colors.reset} Failed to clean replace directives:`, err.message);
  }
  process.exit(1);
});
