#!/usr/bin/env bun
// #MISE description="Manage release tags for multi-module repo"
// #USAGE flag "--dry-run" help="Show what would be done without making changes"
// #USAGE flag "--json" help="Output results as JSON"
// #USAGE flag "--no-verify" help="Skip pre-push hooks when pushing"
// #USAGE arg "<action>" help="Action: create, delete, recreate, list, push"
// #USAGE arg "<version>" help="Version to tag (e.g., v0.4.0-alpha.1)"
// #USAGE arg "[commit]" help="Optional commit to tag (defaults to HEAD)"

import { $, Glob } from "bun";
import { parseArgs } from "util";
import { dirname } from "path";

// Parse arguments
const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    "dry-run": { type: "boolean", default: false },
    json: { type: "boolean", default: false },
    "no-verify": { type: "boolean", default: true }, // Default to no-verify for releases
    verify: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
  strict: true,
  allowPositionals: true,
});

if (values.help || positionals.length < 2) {
  console.log(`release-tags - Manage release tags for Morphir multi-module repo

Usage: mise run release:tags [OPTIONS] <action> <version> [commit]

Actions:
  create    Create all module tags locally
  delete    Delete all module tags (local and remote)
  recreate  Delete and recreate all module tags
  list      List all tags for a version
  push      Push all module tags to remote

Options:
  --dry-run    Show what would be done without making changes
  --json       Output results as JSON
  --no-verify  Skip pre-push hooks when pushing (default)
  --verify     Run pre-push hooks when pushing
  -h, --help   Show this help message

Arguments:
  version    Version to tag (e.g., v0.4.0-alpha.1)
  commit     Optional commit to tag (defaults to HEAD)

Examples:
  mise run release:tags create v0.4.0-alpha.1
  mise run release:tags -- --dry-run create v0.4.0-alpha.1
  mise run release:tags -- --json list v0.4.0-alpha.1`);
  process.exit(positionals.length < 2 ? 1 : 0);
}

const action = positionals[0];
const version = positionals[1];
let commit = positionals[2] || "HEAD";

const dryRun = values["dry-run"];
const jsonOutput = values.json;
const noVerify = values.verify ? false : values["no-verify"];

// Colors
const colors = {
  red: jsonOutput ? "" : "\x1b[0;31m",
  green: jsonOutput ? "" : "\x1b[0;32m",
  yellow: jsonOutput ? "" : "\x1b[1;33m",
  blue: jsonOutput ? "" : "\x1b[0;34m",
  reset: jsonOutput ? "" : "\x1b[0m",
};

// Validate version format
const versionPattern = /^v\d+\.\d+\.\d+(-[\w.]+)?$/;
if (!versionPattern.test(version)) {
  console.error(`${colors.red}ERROR:${colors.reset} Invalid version format: ${version}`);
  console.error("Expected format: v1.2.3 or v1.2.3-alpha.1");
  process.exit(1);
}

// Resolve commit
if (commit === "HEAD") {
  commit = (await $`git rev-parse HEAD`.text()).trim();
}
const commitShort = (await $`git rev-parse --short ${commit}`.text()).trim();

// Auto-detect modules from go.mod files
async function findModules(): Promise<string[]> {
  const glob = new Glob("**/go.mod");
  const modFiles: string[] = [];
  for await (const file of glob.scan({ cwd: ".", onlyFiles: true })) {
    if (
      !file.includes("node_modules/") &&
      !file.includes("vendor/") &&
      !file.includes("tests/")
    ) {
      modFiles.push(file);
    }
  }
  return modFiles
    .map((f) => dirname(f))
    .filter((m) => m.startsWith("pkg/") || m.startsWith("cmd/"))
    .sort();
}

// Results tracking
interface TagResult {
  tag: string;
  action: string;
  status: "success" | "failed" | "dry_run" | "skipped" | "missing" | "found";
  message: string;
}

const results: TagResult[] = [];

function addResult(tag: string, action: string, status: TagResult["status"], message: string) {
  results.push({ tag, action, status, message });
}

function info(msg: string) {
  if (!jsonOutput) console.log(`${colors.blue}→${colors.reset} ${msg}`);
}

function success(msg: string) {
  if (!jsonOutput) console.log(`${colors.green}✓${colors.reset} ${msg}`);
}

function error(msg: string) {
  if (!jsonOutput) console.log(`${colors.red}✗${colors.reset} ${msg}`);
}

function dryRunPrefix(): string {
  return dryRun ? "[DRY-RUN] " : "";
}

// Get all tags for a version
function getAllTags(modules: string[]): string[] {
  return [version, ...modules.map((m) => `${m}/${version}`)];
}

// Create tags
async function createTags(modules: string[]) {
  if (!jsonOutput) {
    console.log("");
    console.log(`${dryRunPrefix()}Creating tags for ${version} on commit ${commitShort}`);
    console.log("");
  }

  let created = 0;
  let failed = 0;

  // Main version tag
  info(`${dryRunPrefix()}Creating tag: ${version}`);
  if (dryRun) {
    success(`Would create: ${version}`);
    addResult(version, "create", "dry_run", "would create");
  } else {
    try {
      await $`git tag -a ${version} -m ${"Release " + version} ${commit}`.quiet();
      success(`Created: ${version}`);
      addResult(version, "create", "success", "created");
      created++;
    } catch {
      error(`Failed to create: ${version} (may already exist)`);
      addResult(version, "create", "failed", "may already exist");
      failed++;
    }
  }

  // Module tags
  for (const module of modules) {
    const tag = `${module}/${version}`;
    info(`${dryRunPrefix()}Creating tag: ${tag}`);
    if (dryRun) {
      success(`Would create: ${tag}`);
      addResult(tag, "create", "dry_run", "would create");
    } else {
      try {
        await $`git tag -a ${tag} -m ${"Release " + module + " " + version} ${commit}`.quiet();
        success(`Created: ${tag}`);
        addResult(tag, "create", "success", "created");
        created++;
      } catch {
        error(`Failed to create: ${tag} (may already exist)`);
        addResult(tag, "create", "failed", "may already exist");
        failed++;
      }
    }
  }

  if (!jsonOutput) {
    console.log("");
    if (dryRun) {
      console.log(`Would create ${modules.length + 1} tags on commit ${commitShort}`);
    } else {
      console.log(`Created ${created} tags on commit ${commitShort}`);
    }
  }

  return { created, failed };
}

// Delete tags
async function deleteTags(modules: string[], deleteRemote = true) {
  if (!jsonOutput) {
    console.log("");
    console.log(`${dryRunPrefix()}Deleting tags for ${version}`);
    console.log("");
  }

  const tags = getAllTags(modules);

  // Delete local tags
  info(`${dryRunPrefix()}Deleting local tags...`);
  for (const tag of tags) {
    if (dryRun) {
      try {
        await $`git rev-parse ${tag}`.quiet();
        success(`Would delete local: ${tag}`);
        addResult(tag, "delete_local", "dry_run", "would delete");
      } catch {
        // Tag doesn't exist locally
      }
    } else {
      try {
        await $`git tag -d ${tag}`.quiet();
        success(`Deleted local: ${tag}`);
        addResult(tag, "delete_local", "success", "deleted");
      } catch {
        // Tag didn't exist
      }
    }
  }

  // Delete remote tags
  if (deleteRemote) {
    info(`${dryRunPrefix()}Deleting remote tags...`);
    const remoteRefs = tags.map((t) => `:refs/tags/${t}`);

    if (dryRun) {
      success(`Would delete ${tags.length} remote tags`);
      for (const tag of tags) {
        addResult(tag, "delete_remote", "dry_run", "would delete");
      }
    } else {
      try {
        const verifyFlag = noVerify ? ["--no-verify"] : [];
        await $`git push origin ${remoteRefs} ${verifyFlag}`.quiet();
        success(`Deleted ${tags.length} remote tags`);
        for (const tag of tags) {
          addResult(tag, "delete_remote", "success", "deleted");
        }
      } catch {
        error("Some remote tags may not have existed");
        for (const tag of tags) {
          addResult(tag, "delete_remote", "skipped", "may not have existed");
        }
      }
    }
  }

  if (!jsonOutput) {
    console.log("");
    if (dryRun) {
      console.log(`Would delete ${modules.length + 1} tags`);
    } else {
      console.log(`Deleted ${modules.length + 1} tags`);
    }
  }
}

// Recreate tags
async function recreateTags(modules: string[]) {
  if (!jsonOutput) {
    console.log("");
    console.log(`${dryRunPrefix()}Recreating tags for ${version} on commit ${commitShort}`);
  }

  await deleteTags(modules, true);

  if (!jsonOutput) console.log("");

  // Reset results for create phase
  results.length = 0;

  await createTags(modules);
}

// List tags
async function listTags(modules: string[]) {
  if (!jsonOutput) {
    console.log("");
    console.log(`Tags for ${version}:`);
    console.log("");
  }

  let found = 0;
  let missing = 0;

  // Check main tag
  try {
    const tagCommit = (await $`git rev-parse ${version}`.text()).trim();
    if (!jsonOutput) {
      console.log(`  ${colors.green}✓${colors.reset} ${version} -> ${tagCommit.substring(0, 8)}`);
    }
    addResult(version, "list", "found", tagCommit.substring(0, 8));
    found++;
  } catch {
    if (!jsonOutput) {
      console.log(`  ${colors.red}✗${colors.reset} ${version} (not found)`);
    }
    addResult(version, "list", "missing", "not found");
    missing++;
  }

  // Check module tags
  for (const module of modules) {
    const tag = `${module}/${version}`;
    try {
      const tagCommit = (await $`git rev-parse ${tag}`.text()).trim();
      if (!jsonOutput) {
        console.log(`  ${colors.green}✓${colors.reset} ${tag} -> ${tagCommit.substring(0, 8)}`);
      }
      addResult(tag, "list", "found", tagCommit.substring(0, 8));
      found++;
    } catch {
      if (!jsonOutput) {
        console.log(`  ${colors.red}✗${colors.reset} ${tag} (not found)`);
      }
      addResult(tag, "list", "missing", "not found");
      missing++;
    }
  }

  if (!jsonOutput) {
    console.log("");
    console.log(`Found: ${found}, Missing: ${missing}`);
  }

  return { found, missing };
}

// Push tags
async function pushTags(modules: string[]) {
  if (!jsonOutput) {
    console.log("");
    console.log(`${dryRunPrefix()}Pushing tags for ${version}`);
    console.log("");
  }

  const tags = getAllTags(modules);
  const existingTags: string[] = [];
  const missingTags: string[] = [];

  // Check which tags exist locally
  for (const tag of tags) {
    try {
      await $`git rev-parse ${tag}`.quiet();
      existingTags.push(tag);
    } catch {
      missingTags.push(tag);
    }
  }

  // Report missing tags
  for (const tag of missingTags) {
    if (!jsonOutput) {
      console.log(`${colors.yellow}WARN:${colors.reset} Tag ${tag} does not exist locally, skipping`);
    }
    addResult(tag, "push", "skipped", "not found locally");
  }

  if (existingTags.length === 0) {
    error("No tags found to push");
    if (jsonOutput) {
      outputJson("error", "push", modules);
    }
    process.exit(1);
  }

  // Push all existing tags
  info(`${dryRunPrefix()}Pushing ${existingTags.length} tags to origin...`);

  if (dryRun) {
    success(`Would push ${existingTags.length} tags`);
    for (const tag of existingTags) {
      addResult(tag, "push", "dry_run", "would push");
    }
  } else {
    try {
      const verifyFlag = noVerify ? ["--no-verify"] : [];
      await $`git push origin --tags ${verifyFlag}`;
      success(`Pushed ${existingTags.length} tags`);
      for (const tag of existingTags) {
        addResult(tag, "push", "success", "pushed");
      }
    } catch {
      error("Failed to push some tags");
      for (const tag of existingTags) {
        addResult(tag, "push", "failed", "push failed");
      }
    }
  }

  if (!jsonOutput) {
    console.log("");
    if (!dryRun) {
      console.log("To trigger the release workflow:");
      console.log(`  gh workflow run release.yml --field tag=${version}`);
    }
  }
}

// JSON output
function outputJson(status: string, actionName: string, modules: string[]) {
  console.log(JSON.stringify({
    version,
    commit: commitShort,
    action: actionName,
    dry_run: dryRun,
    status,
    total_tags: modules.length + 1,
    results,
  }, null, 2));
}

// Main
async function main() {
  const modules = await findModules();

  switch (action) {
    case "create":
      await createTags(modules);
      if (!jsonOutput && !dryRun) {
        console.log("");
        console.log("Next steps:");
        console.log(`  1. Push tags: mise run release:tags push ${version}`);
        console.log(`  2. Trigger release: gh workflow run release.yml --field tag=${version}`);
      }
      break;

    case "delete":
      await deleteTags(modules, true);
      break;

    case "recreate":
      await recreateTags(modules);
      if (!jsonOutput && !dryRun) {
        console.log("");
        console.log("Next steps:");
        console.log(`  1. Push tags: mise run release:tags push ${version}`);
        console.log(`  2. Trigger release: gh workflow run release.yml --field tag=${version}`);
      }
      break;

    case "list":
      await listTags(modules);
      break;

    case "push":
      await pushTags(modules);
      break;

    default:
      console.error(`${colors.red}ERROR:${colors.reset} Unknown action: ${action}`);
      console.error("Actions: create, delete, recreate, list, push");
      process.exit(1);
  }

  if (jsonOutput) {
    const hasFailures = results.some((r) => r.status === "failed");
    const hasMissing = results.some((r) => r.status === "missing");
    const status = hasFailures ? "error" : hasMissing ? "partial" : "success";
    outputJson(status, action, modules);
  }
}

main().catch((err) => {
  console.error("Tag operation failed:", err.message);
  process.exit(1);
});
