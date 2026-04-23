/**
 * Corpus — locate a package's root directory and enumerate its
 * authored markdown files.
 */
import { readdir, stat } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

import type { Manifest } from "./manifest.js";
import { readManifest } from "./manifest.js";

/** File names and directories relative to the corpus root. */
export const MANIFEST_FILE = "substrate.toml";
export const LOCKFILE_FILE = "substrate.lock";
export const PACKAGES_DIR = join("substrate", "packages");

/** Directories skipped when walking the corpus. */
const SKIP_DIRS: ReadonlySet<string> = new Set([
    ".git",
    "node_modules",
    "dist",
]);

/**
 * A located package: its root directory and parsed manifest.
 */
export interface LocatedPackage {
    readonly root: string;
    readonly manifestPath: string;
    readonly manifest: Manifest;
}

/**
 * Locate the nearest enclosing package by walking up from `startDir`
 * until a `substrate.toml` is found.
 *
 * Throws if no manifest is found up to the filesystem root.
 */
export async function locatePackage(startDir: string): Promise<LocatedPackage> {
    let dir = resolve(startDir);
    // eslint-disable-next-line no-constant-condition
    while (true) {
        const manifestPath = join(dir, MANIFEST_FILE);
        if (await fileExists(manifestPath)) {
            const manifest = await readManifest(manifestPath);
            return { root: dir, manifestPath, manifest };
        }
        const parent = dirname(dir);
        if (parent === dir) {
            throw new Error(
                `No ${MANIFEST_FILE} found in ${startDir} or any parent directory`,
            );
        }
        dir = parent;
    }
}

/**
 * Walk `root` and return every `.md` file, optionally skipping files
 * under the vendored packages tree.
 */
export async function listMarkdownFiles(
    root: string,
    options: { readonly includeVendored?: boolean } = {},
): Promise<readonly string[]> {
    const absRoot = resolve(root);
    const vendoredRoot = join(absRoot, PACKAGES_DIR);
    const out: string[] = [];

    async function walk(dir: string): Promise<void> {
        const entries = await readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                if (SKIP_DIRS.has(entry.name)) continue;
                if (!options.includeVendored && full === vendoredRoot) continue;
                await walk(full);
            } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
                out.push(full);
            }
        }
    }

    await walk(absRoot);
    out.sort((a, b) => a.localeCompare(b));
    return out;
}

/**
 * Compute the on-disk location for an installed package's vendored
 * content, given the corpus root and the scoped package name.
 */
export function vendoredPath(corpusRoot: string, packageName: string): string {
    const match = /^@([^/]+)\/([^/]+)$/.exec(packageName);
    if (match === null) {
        throw new Error(`Invalid scoped package name: ${packageName}`);
    }
    const [, scope, name] = match;
    return join(corpusRoot, PACKAGES_DIR, `@${scope!}`, name!);
}

async function fileExists(path: string): Promise<boolean> {
    try {
        const s = await stat(path);
        return s.isFile();
    } catch {
        return false;
    }
}

// `sep` is re-exported so callers can build paths consistent with the
// platform separator if they need to.
export { sep };
