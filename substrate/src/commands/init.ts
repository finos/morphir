/**
 * `substrate init` — scaffold a new package in the current directory.
 *
 * Behaviour per `specs/tools/cli/packages.md`:
 *
 * - Aborts without writing anything if `substrate.json` already exists.
 * - Prompts for name, kind, and (for libraries) version.
 * - Pass `--yes` to accept all defaults without prompting.
 * - Writes `substrate.json` and creates an empty `substrate/` directory.
 */
import { createInterface } from "node:readline/promises";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { spawn } from "node:child_process";

import { MANIFEST_FILE } from "../package/corpus.js";
import type { Manifest, PackageKind } from "../package/manifest.js";
import { formatManifest, isValidPackagePath } from "../package/manifest.js";

export interface InitResult {
    readonly root: string;
    readonly manifest: Manifest;
}

export interface InitOptions {
    readonly yes?: boolean;
}

export async function init(startDir: string, options: InitOptions = {}): Promise<InitResult> {
    const manifestPath = join(startDir, MANIFEST_FILE);

    if (await fileExists(manifestPath)) {
        throw new Error(
            `${MANIFEST_FILE} already exists in ${startDir}; ` +
                "remove it or run from a different directory.",
        );
    }

    const defaultName = await deriveDefaultName(startDir);
    const manifest = options.yes
        ? buildDefaultManifest(defaultName)
        : await promptForManifest(defaultName);

    await writeFile(manifestPath, formatManifest(manifest), "utf8");
    await mkdir(join(startDir, "substrate"), { recursive: true });

    return { root: startDir, manifest };
}

// ---------------------------------------------------------------------------
// Prompt helpers
// ---------------------------------------------------------------------------

async function promptForManifest(defaultName: string): Promise<Manifest> {
    const rl = createInterface({ input: process.stdin, output: process.stdout });

    try {
        const name = await ask(rl, `Package name (${defaultName}): `, defaultName);
        if (!isValidPackagePath(name)) {
            throw new Error(
                `Package name must be a non-empty path with no leading/trailing ` +
                    `slashes or ".." segments, got "${name}"`,
            );
        }

        const kindRaw = await ask(rl, "Kind [corpus/library] (corpus): ", "corpus");
        if (kindRaw !== "corpus" && kindRaw !== "library") {
            throw new Error(`Kind must be "corpus" or "library", got "${kindRaw}"`);
        }
        const kind: PackageKind = kindRaw;

        if (kind === "library") {
            const version = await ask(rl, "Version (0.1.0): ", "0.1.0");
            return { name, kind, version, dependencies: [] };
        }
        return { name, kind, dependencies: [] };
    } finally {
        rl.close();
    }
}

function buildDefaultManifest(defaultName: string): Manifest {
    return { name: defaultName, kind: "corpus", dependencies: [] };
}

async function ask(
    rl: ReturnType<typeof createInterface>,
    prompt: string,
    defaultValue: string,
): Promise<string> {
    const answer = await rl.question(prompt);
    return answer.trim() === "" ? defaultValue : answer.trim();
}

// ---------------------------------------------------------------------------
// Default name derivation
// ---------------------------------------------------------------------------

async function deriveDefaultName(dir: string): Promise<string> {
    const dirName = basename(dir);
    const org = await gitRemoteOrg(dir);
    return org !== null ? `${org}/${dirName}` : dirName;
}

async function gitRemoteOrg(cwd: string): Promise<string | null> {
    try {
        const url = await runCommand("git", ["remote", "get-url", "origin"], cwd);
        return parseOrgFromRemoteUrl(url.trim());
    } catch {
        return null;
    }
}

function parseOrgFromRemoteUrl(url: string): string | null {
    // https://github.com/Org/repo.git  or  git@github.com:Org/repo.git
    const httpsMatch = /github\.com\/([^/]+)\//.exec(url);
    if (httpsMatch) return httpsMatch[1]!;
    const sshMatch = /github\.com:([^/]+)\//.exec(url);
    if (sshMatch) return sshMatch[1]!;
    return null;
}

function runCommand(cmd: string, args: string[], cwd: string): Promise<string> {
    return new Promise((resolve, reject) => {
        const child = spawn(cmd, args, {
            cwd,
            stdio: ["ignore", "pipe", "pipe"],
        });
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (chunk: Buffer) => { stdout += chunk.toString("utf8"); });
        child.stderr.on("data", (chunk: Buffer) => { stderr += chunk.toString("utf8"); });
        child.on("error", reject);
        child.on("close", (code) => {
            if (code === 0) resolve(stdout);
            else reject(new Error(`${cmd} exited with code ${code}: ${stderr.trim()}`));
        });
    });
}

async function fileExists(path: string): Promise<boolean> {
    try {
        const s = await stat(path);
        return s.isFile();
    } catch {
        return false;
    }
}
