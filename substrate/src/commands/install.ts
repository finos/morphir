/**
 * `substrate install` — resolve and vendor every declared dependency
 * into `substrate/`.
 *
 * Behaviour per `specs/tools/cli/packages.md`:
 *
 * - When a lockfile is present, it is authoritative: each dependency
 *   is installed at the recorded commit.
 * - When no lockfile is present, each manifest range is resolved
 *   against the remote's tags (for semver ranges) or used directly
 *   as a branch ref, the lockfile is written, and the resolved
 *   versions are installed.
 * - The command is idempotent: repeated runs with an unchanged
 *   manifest and lockfile yield no changes.
 */
import { cp, mkdir, mkdtemp, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

import {
    LOCKFILE_FILE,
    MANIFEST_FILE,
    locatePackage,
    vendoredPath,
} from "../package/corpus.js";
import { cloneAtRef, listRemoteTags, repoUrl, resolveRefToCommit } from "../package/git.js";
import { computeIntegrity } from "../package/integrity.js";
import {
    lockfileExists,
    readLockfile,
    writeLockfile,
} from "../package/lockfile.js";
import type { LockEntry, Lockfile } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { readManifest } from "../package/manifest.js";
import { isBranchRef, pickBestTag } from "../package/resolve.js";

export interface InstallResult {
    readonly root: string;
    readonly installed: readonly InstalledEntry[];
    readonly wroteLockfile: boolean;
}

export interface InstalledEntry {
    readonly name: string;
    readonly installName: string;
    readonly resolved: string;
    readonly action: "installed" | "already-present";
}

/**
 * Run install against the package containing `startDir`.
 */
export async function install(startDir: string): Promise<InstallResult> {
    const pkg = await locatePackage(startDir);
    const lockPath = join(pkg.root, LOCKFILE_FILE);

    if (await lockfileExists(lockPath)) {
        const lock = await readLockfile(lockPath);
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

/**
 * Install every dependency recorded in `lock`. Skips any dependency
 * whose vendored tree already matches the lockfile's integrity.
 */
async function installFromLock(
    root: string,
    lock: Lockfile,
): Promise<readonly InstalledEntry[]> {
    const out: InstalledEntry[] = [];
    for (const entry of lock.packages) {
        const dest = vendoredPath(root, entry.installName);
        if (await pathExists(dest)) {
            const integrity = await computeIntegrity(dest);
            if (integrity === entry.integrity) {
                out.push({
                    name: entry.name,
                    installName: entry.installName,
                    resolved: entry.resolved,
                    action: "already-present",
                });
                continue;
            }
            await rm(dest, { recursive: true, force: true });
        }
        await fetchInto(entry.name, entry.resolved, dest);
        out.push({
            name: entry.name,
            installName: entry.installName,
            resolved: entry.resolved,
            action: "installed",
        });
    }
    return out;
}

/**
 * Resolve every manifest dependency's range against remote tags (or as a
 * branch ref) and install the selected version.
 */
async function resolveAndInstall(
    root: string,
    dependencies: readonly DependencySpec[],
): Promise<{ readonly entries: LockEntry[]; readonly installed: InstalledEntry[] }> {
    const entries: LockEntry[] = [];
    const installed: InstalledEntry[] = [];

    for (const dep of dependencies) {
        const { ref, commit, resolved } = await resolveDepRef(dep);
        const { installName, dest } = await fetchAndInstall(dep.name, ref, root);
        const integrity = await computeIntegrity(dest);
        entries.push({
            name: dep.name,
            installName,
            requested: dep.range,
            resolved,
            commit,
            integrity,
        });
        installed.push({ name: dep.name, installName, resolved, action: "installed" });
    }

    return { entries, installed };
}

// ---------------------------------------------------------------------------
// Resolution helpers
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
// Fetch helpers
// ---------------------------------------------------------------------------

/**
 * Clone `depName` at `ref` into a temp directory, read the package's own
 * manifest to discover its declared name and optional `subdir`, then copy
 * the relevant content into `substrate/<installName>`.
 *
 * Returns the install name and the final destination path.
 */
async function fetchAndInstall(
    depName: string,
    ref: string,
    corpusRoot: string,
): Promise<{ installName: string; dest: string }> {
    const url = repoUrl(depName);
    const tempBase = await mkdtemp(join(tmpdir(), "substrate-fetch-"));
    const tempClone = join(tempBase, "clone");

    try {
        await cloneAtRef(url, ref, tempClone);
        await rm(join(tempClone, ".git"), { recursive: true, force: true });

        const { installName, subdir } = await readPackageMeta(tempClone, depName);
        const dest = vendoredPath(corpusRoot, installName);

        if (await pathExists(dest)) {
            await rm(dest, { recursive: true, force: true });
        }
        await mkdir(dest, { recursive: true });

        const source = subdir ? join(tempClone, subdir) : tempClone;
        await cp(source, dest, { recursive: true });

        return { installName, dest };
    } finally {
        await rm(tempBase, { recursive: true, force: true });
    }
}

/**
 * Thin wrapper used by `installFromLock` where we already know the
 * `installName` and `dest` from the lockfile — just (re-)clone and copy.
 */
async function fetchInto(
    depName: string,
    ref: string,
    dest: string,
): Promise<void> {
    const url = repoUrl(depName);
    const tempBase = await mkdtemp(join(tmpdir(), "substrate-fetch-"));
    const tempClone = join(tempBase, "clone");

    try {
        await cloneAtRef(url, ref, tempClone);
        await rm(join(tempClone, ".git"), { recursive: true, force: true });

        const { subdir } = await readPackageMeta(tempClone, depName);
        await mkdir(dirname(dest), { recursive: true });

        if (await pathExists(dest)) {
            await rm(dest, { recursive: true, force: true });
        }
        await mkdir(dest, { recursive: true });

        const source = subdir ? join(tempClone, subdir) : tempClone;
        await cp(source, dest, { recursive: true });
    } finally {
        await rm(tempBase, { recursive: true, force: true });
    }
}

/**
 * Read the package's own manifest from `cloneDir` to obtain its declared
 * name and optional `subdir`. Falls back to `depName` when no manifest
 * is present or it cannot be parsed.
 */
async function readPackageMeta(
    cloneDir: string,
    depName: string,
): Promise<{ installName: string; subdir: string | undefined }> {
    try {
        const manifest = await readManifest(join(cloneDir, MANIFEST_FILE));
        return { installName: manifest.name, subdir: manifest.subdir };
    } catch {
        return { installName: depName, subdir: undefined };
    }
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
