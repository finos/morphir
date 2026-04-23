/**
 * Thin wrappers around the `git` binary for package operations.
 *
 * We shell out rather than linking a git library to keep dependencies
 * light and match any authentication the user has configured (SSH
 * agents, credential helpers, etc.).
 */
import { spawn } from "node:child_process";

/** Host used to build clone URLs for scoped package names. */
const GITHUB_HOST = "https://github.com";

/**
 * Build the clone URL for a scoped package `@scope/name`.
 */
export function repoUrl(packageName: string): string {
    const match = /^@([^/]+)\/([^/]+)$/.exec(packageName);
    if (match === null) {
        throw new Error(`Invalid scoped package name: ${packageName}`);
    }
    const [, scope, name] = match;
    return `${GITHUB_HOST}/${scope!}/${name!}.git`;
}

/** A tag discovered on a remote repository. */
export interface RemoteTag {
    readonly tag: string;
    readonly commit: string;
}

/**
 * List tags available on a remote repository. Uses
 * `git ls-remote --tags --refs`.
 */
export async function listRemoteTags(url: string): Promise<readonly RemoteTag[]> {
    const out = await runGit(["ls-remote", "--tags", "--refs", url]);
    const tags: RemoteTag[] = [];
    for (const line of out.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (trimmed.length === 0) continue;
        const match = /^([0-9a-f]+)\s+refs\/tags\/(.+)$/.exec(trimmed);
        if (match === null) continue;
        const [, commit, tag] = match;
        tags.push({ commit: commit!, tag: tag! });
    }
    return tags;
}

/**
 * Shallow-clone a repository at the given tag or ref into `destination`.
 */
export async function cloneAtRef(
    url: string,
    ref: string,
    destination: string,
): Promise<void> {
    await runGit([
        "clone",
        "--depth",
        "1",
        "--branch",
        ref,
        url,
        destination,
    ]);
}

/**
 * Create an annotated tag on HEAD and push it.
 */
export async function createAndPushTag(
    cwd: string,
    tag: string,
    message: string,
): Promise<void> {
    await runGit(["tag", "-a", tag, "-m", message], cwd);
    await runGit(["push", "origin", tag], cwd);
}

/** Returns true when the working tree at `cwd` is clean. */
export async function isWorkingTreeClean(cwd: string): Promise<boolean> {
    const out = await runGit(["status", "--porcelain"], cwd);
    return out.trim().length === 0;
}

// ---------------------------------------------------------------------------
// Internal runner
// ---------------------------------------------------------------------------

function runGit(args: readonly string[], cwd?: string): Promise<string> {
    return new Promise((resolve, reject) => {
        const child = spawn("git", args, {
            cwd: cwd ?? process.cwd(),
            stdio: ["ignore", "pipe", "pipe"],
        });
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (chunk: Buffer) => {
            stdout += chunk.toString("utf8");
        });
        child.stderr.on("data", (chunk: Buffer) => {
            stderr += chunk.toString("utf8");
        });
        child.on("error", (err) => reject(err));
        child.on("close", (code) => {
            if (code === 0) {
                resolve(stdout);
            } else {
                reject(
                    new Error(
                        `git ${args.join(" ")} exited with code ${code}: ${stderr.trim() || stdout.trim()}`,
                    ),
                );
            }
        });
    });
}
