#!/usr/bin/env bun
import { $ } from "bun";
import Bun from "bun";
import { parseArgs } from "util";
import { existsSync } from "node:fs";
import { resolve } from "path";
import { cwd, platform } from "node:process";

const isWin = process.platform === "win32";

const DEFAULT_MILL_VERSION = process.env.DEFAULT_MILL_VERSION || "0.11.6";
const GITHUB_RELEASE_CDN = process.env.GITHUB_RELEASE_CDN || "";
const MILL_REPO_URL =
  process.env.MILL_REPO_URL || "https://github.com/com-lihaoyi/mill";

type ResolveMillVersionResult = {
  millVersion: string;
  remainingArgs: string[];
};

async function resolveMillVersion(
  args: string[]
): Promise<ResolveMillVersionResult> {
  const preArgs = args.slice(0, 2);
  let remainingArgs = args;
  let millVersion: string | undefined = undefined;
  let millVersionOptionProvided = false;
  let values: {
    "mill-version"?: string;
  } = {};

  if (args.length > 1 && args[0] === "--mill-version") {
    let parseResults = parseArgs({
      args: args.slice(0, 2),
      options: {
        "mill-version": {
          type: "string",
        },
      },
      allowPositionals: true,
      tokens: true,
    });
    values = parseResults.values;
  }

  // Attempt to get the mill version from the command line arguments
  if (values?.["mill-version"]) {
    millVersion = values["mill-version"];
    millVersionOptionProvided = true;
  }

  // If not already set, try to get the mill version by reading the .mill-version file
  if (!millVersion) {
    let millVersionFile = resolve(cwd(), ".mill-version");
    if (existsSync(millVersionFile)) {
      millVersion = (await Bun.file(millVersionFile).text()).trim();
    } else {
      millVersion = resolve(cwd(), ".config", ".mill-version");
      if (existsSync(millVersionFile)) {
        millVersion = (await Bun.file(millVersionFile).text()).trim();
      }
    }
  }

  // If not already set just fallback to the DEFAULT_MILL_VERSION
  if (!millVersion) {
    millVersion = DEFAULT_MILL_VERSION;
  }

  return millVersionOptionProvided
    ? { millVersion, remainingArgs: args.slice(2) }
    : { millVersion, remainingArgs: args };
}

async function getLatestReleasedMillVersion(): Promise<string | undefined> {
  const url = `${MILL_REPO_URL}/releases/latest`;
  const response = await fetch(url);
  const responseUrl = response.url;
  const matches = responseUrl.match(/\/releases\/tag\/(.*)$/);
  if (matches && matches.length > 1) {
    return matches[1];
  }
  return undefined;
}

const { millVersion, remainingArgs } = await resolveMillVersion(
  Bun.argv.slice(2)
);

let latest = await getLatestReleasedMillVersion();
console.log("latest: ", latest);

console.log("remainingArgs: ", remainingArgs);
