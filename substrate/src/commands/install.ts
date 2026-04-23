/**
 * `substrate install` — resolve and vendor every declared dependency
 * into `substrate/`.
 *
 * Behaviour per `specs/tools/cli/packages.md`:
 *
 * - When a lockfile is present and valid, it is authoritative: each
 *   dependency is re-installed at the recorded ref if any of its
 *   installed sub-packages is missing or has stale integrity.
 * - When no lockfile is present (or it cannot be parsed), each manifest
 *   range is resolved and the lockfile is written.
 * - Every `substrate.json` found inside a cloned repository is treated
 *   as a sub-package. If two sub-packages declare the same name their
 *   file trees are merged; clashing paths within the same declared name
 *   are an error.
 * - The command is idempotent: repeated runs with an unchanged manifest
 *   and lockfile yield no changes.
 */
import { cp, mkdir, mkdtemp, readdir, rm } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { tmpdir } from "node:os";

import {
    LOCKFILE_FILE,
    MANIFEST_FILE,
    locatePackage,
    vendoredPath,
} from "../package/corpus.js";
import {
    cloneAtRef,
    listRemoteTags,
    repoUrl,
    resolveRefToCommit,
} from "../package/git.js";
import { computeIntegrity } from "../package/integrity.js";
import { lockfileExists, readLockfile, writeLockfile } from "../package/lockfile.js";
import type { LockEntry, LockInstall, Lockfile } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { readManifest } from "../package/manifest.js";
import { isBranchRef, pickBestTag } from "../package/resolve.js";

export interface InstallResult {
    readonly root: string;
    readonly installed: readonly InstalledEntry[];
    readonly wroteLockfile: boolean;
}

export interface InstalledEntry {
    readonly depName: string;
    readonly installName: string;
    readonly resolved: string;
    readonly action: "installed" | "already-present";
}

export async function install(startDir: string): Promise<InstallResult> {
    const pkg = await locatePackage(startDir);
    const lockPath = join(pkg.root, LOCKFILE_FILE);

    let lock: Lockfile | null = null;
    if (await lockfileExists(lockPath)) {
        try {
            lock = await readLockfile(lockPath);
        } catch {
            // Stale or incompatible lockfile — regenerate.
            lock = null;
        }
    }

    if (lock !== null) {
        const installed = await installFromLock(pkg.root, lock);
        return { root: pkg.root, installed, wroteLockfile: false };
    }

    const { entries, installed } = await resolveAndInstall(
        pkg.root,
        pkg.manifest.dependencies,
    );
    await writeLockfile(lockPath, { packages: entries });
    return { root: pkg.root, installed, wroteLockfile: true };
}

// ---------------------------------------------------------------------------
// Install from lockfile
// ---------------------------------------------------------------------------

async function installFromLock(
    root: string,
    lock: Lockfile,
): Promise<readonly InstalledEntry[]> {
    const out: InstalledEntry[] = [];
    for (const entry of lock.packages) {
        const allPresent = await checkInstalls(root, entry.installs);
        if (allPresent) {
            for (const inst of entry.installs) {
                out.push({
                    depName: entry.name,
                    installName: inst.name,
                    resolved: entry.resolved,
                    action: "already-present",
                });
            }
            continue;
        }
        // Remove stale install dirs before re-fetching.
        for (const inst of entry.installs) {
            await rm(vendoredPath(root, inst.name), { recursive: true, force: true });
        }
        const installs = await fetchAndInstall(entry.name, entry.ref, root);
        for (const inst of installs) {
            out.push({
                depName: entry.name,
                installName: inst.installName,
                resolved: entry.resolved,
                action: "installed",
            });
        }
    }
    return out;
}

async function checkInstalls(root: string, installs: readonly LockInstall[]): Promise<boolean> {
    for (const inst of installs) {
        const dest = vendoredPath(root, inst.name);
        if (!(await pathExists(dest))) return false;
        const integrity = await computeIntegrity(dest);
        if (integrity !== inst.integrity) return false;
    }
    return installs.length > 0;
}

// ---------------------------------------------------------------------------
// Resolve and install from manifest
// ---------------------------------------------------------------------------

async function resolveAndInstall(
    root: string,
    dependencies: readonly DependencySpec[],
): Promise<{ readonly entries: LockEntry[]; readonly installed: InstalledEntry[] }> {
    const entries: LockEntry[] = [];
    const installed: InstalledEntry[] = [];

    for (const dep of dependencies) {
        const { ref, commit, resolved } = await resolveDepRef(dep);
        const subInstalls = await fetchAndInstall(dep.name, ref, root);
        const lockInstalls: LockInstall[] = [];
        for (const inst of subInstalls) {
            const integrity = await computeIntegrity(inst.dest);
            lockInstalls.push({ name: inst.installName, integrity });
            installed.push({
                depName: dep.name,
                installName: inst.installName,
                resolved,
                action: "installed",
            });
        }
        entries.push({ name: dep.name, ref, requested: dep.range, resolved, commit, installs: lockInstalls });
    }

    return { entries, installed };
}

// ---------------------------------------------------------------------------
// Ref resolution
// ---------------------------------------------------------------------------

async function resolveDepRef(
    dep: DependencySpec,
): Promise<{ ref: string; commit: string; resolved: string }> {
    const url = repoUrl(dep.name);

    if (isBranchRef(dep.range)) {
        const commit = await resolveRefToCommit(url, dep.range);
        if (commit === null) {
            throw new Error(`Branch "${dep.range}" not found on ${dep.name}`);
        }
        return { ref: dep.range, commit, resolved: commit };
    }

    const tags = await listRemoteTags(url);
    const picked = pickBestTag(tags, dep.range);
    if (picked === null) {
        throw new Error(`No tag on ${dep.name} satisfies range "${dep.range}"`);
    }
    const resolved = picked.tag.startsWith("v") ? picked.tag.slice(1) : picked.tag;
    return { ref: picked.tag, commit: picked.commit, resolved };
}

// ---------------------------------------------------------------------------
// Fetch and install
// ---------------------------------------------------------------------------

export interface SubInstall {
    readonly installName: string;
    readonly dest: string;
}

/**
 * Clone `depName` at `ref`, scan every `substrate.json` inside the clone,
 * merge sub-packages with the same declared name (erroring on path clashes),
 * and copy each into `substrate/<installName>/`.
 */
export async function fetchAndInstall(
    depName: string,
    ref: string,
    corpusRoot: string,
): Promise<SubInstall[]> {
    const url = repoUrl(depName);
    const tempBase = await mkdtemp(join(tmpdir(), "substrate-fetch-"));
    const tempClone = join(tempBase, "clone");

    try {
        await cloneAtRef(url, ref, tempClone);
        await rm(join(tempClone, ".git"), { recursive: true, force: true });

        const subPackages = await scanManifests(tempClone);
        if (subPackages.length === 0) {
            // No manifest found — fall back to using dep name, whole clone.
            subPackages.push({ installName: depName, sourceDir: tempClone });
        }

        const fileMap = await buildFileMap(subPackages);
        const results: SubInstall[] = [];

        for (const [installName, files] of fileMap) {
            const dest = vendoredPath(corpusRoot, installName);
            if (await pathExists(dest)) {
                await rm(dest, { recursive: true, force: true });
            }
            await mkdir(dest, { recursive: true });
            for (const [relPath, absSource] of files) {
                const destFile = join(dest, relPath);
                await mkdir(dirname(destFile), { recursive: true });
                await cp(absSource, destFile);
            }
            results.push({ installName, dest });
        }

        return results;
    } finally {
        await rm(tempBase, { recursive: true, force: true });
    }
}

// ---------------------------------------------------------------------------
// Multi-manifest scanning
// ---------------------------------------------------------------------------

interface SubPackage {
    readonly installName: string;
    readonly sourceDir: string;
}

const SCAN_SKIP = new Set([".git", "node_modules", "substrate", "dist"]);

/**
 * Recursively find every `substrate.json` in `dir` (skipping vendor/tool
 * directories), read each manifest, and return the list of sub-packages
 * with their source directories.
 */
export async function scanManifests(dir: string): Promise<SubPackage[]> {
    const manifestPaths: string[] = [];

    async function walk(d: string): Promise<void> {
        const entries = await readdir(d, { withFileTypes: true });
        for (const entry of entries) {
            const full = join(d, entry.name);
            if (entry.isDirectory()) {
                if (SCAN_SKIP.has(entry.name)) continue;
                await walk(full);
            } else if (entry.isFile() && entry.name === MANIFEST_FILE) {
                manifestPaths.push(full);
            }
        }
    }

    await walk(dir);

    const results: SubPackage[] = [];
    for (const manifestPath of manifestPaths) {
        try {
            const manifest = await readManifest(manifestPath);
            const manifestDir = dirname(manifestPath);
            const sourceDir = manifest.subdir
                ? join(manifestDir, manifest.subdir)
                : manifestDir;
            results.push({ installName: manifest.name, sourceDir });
        } catch {
            // Unreadable or invalid manifest — skip.
        }
    }
    return results;
}

/**
 * Build a map of `installName → Map<relPath, absSourcePath>` from a list
 * of sub-packages. Throws when two sub-packages with the same `installName`
 * produce a file at the same relative path.
 */
async function buildFileMap(
    subPackages: SubPackage[],
): Promise<Map<string, Map<string, string>>> {
    const result = new Map<string, Map<string, string>>();

    for (const pkg of subPackages) {
        if (!result.has(pkg.installName)) {
            result.set(pkg.installName, new Map());
        }
        const files = result.get(pkg.installName)!;
        const walked = await walkFiles(pkg.sourceDir);
        for (const absPath of walked) {
            const relPath = relative(pkg.sourceDir, absPath);
            if (files.has(relPath)) {
                throw new Error(
                    `Package name clash: "${relPath}" appears in two sub-packages ` +
                        `both declaring name "${pkg.installName}"`,
                );
            }
            files.set(relPath, absPath);
        }
    }

    return result;
}

async function walkFiles(dir: string): Promise<string[]> {
    const out: string[] = [];
    async function walk(d: string): Promise<void> {
        const entries = await readdir(d, { withFileTypes: true });
        for (const entry of entries) {
            const full = join(d, entry.name);
            if (entry.isDirectory()) {
                await walk(full);
            } else if (entry.isFile()) {
                out.push(full);
            }
        }
    }
    await walk(dir);
    return out;
}

async function pathExists(path: string): Promise<boolean> {
    try {
        const { access } = await import("node:fs/promises");
        await access(path);
        return true;
    } catch {
        return false;
    }
}
