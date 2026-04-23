/**
 * `substrate install` — resolve and vendor every declared dependency
 * into `substrate/packages/`.
 *
 * Behaviour per `specs/tools/packages.md`:
 *
 * - When a lockfile is present, it is authoritative: each dependency
 *   is installed at the recorded commit.
 * - When no lockfile is present, each manifest range is resolved
 *   against the remote's tags, the lockfile is written, and the
 *   resolved versions are installed.
 * - The command is idempotent: repeated runs with an unchanged
 *   manifest and lockfile yield no changes.
 */
import { access, mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";

import {
    LOCKFILE_FILE,
    locatePackage,
    vendoredPath,
} from "../package/corpus.js";
import { cloneAtRef, listRemoteTags, repoUrl } from "../package/git.js";
import { computeIntegrity } from "../package/integrity.js";
import {
    lockfileExists,
    readLockfile,
    writeLockfile,
} from "../package/lockfile.js";
import type { LockEntry, Lockfile } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { pickBestTag } from "../package/resolve.js";

export interface InstallResult {
    readonly root: string;
    readonly installed: readonly InstalledEntry[];
    readonly wroteLockfile: boolean;
}

export interface InstalledEntry {
    readonly name: string;
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
        const dest = vendoredPath(root, entry.name);
        if (await pathExists(dest)) {
            const integrity = await computeIntegrity(dest);
            if (integrity === entry.integrity) {
                out.push({
                    name: entry.name,
                    resolved: entry.resolved,
                    action: "already-present",
                });
                continue;
            }
            await rm(dest, { recursive: true, force: true });
        }
        await fetchInto(entry.name, entry.resolved, dest);
        out.push({ name: entry.name, resolved: entry.resolved, action: "installed" });
    }
    return out;
}

/**
 * Resolve every manifest dependency's range against remote tags and
 * install the selected version.
 */
async function resolveAndInstall(
    root: string,
    dependencies: readonly DependencySpec[],
): Promise<{ readonly entries: LockEntry[]; readonly installed: InstalledEntry[] }> {
    const entries: LockEntry[] = [];
    const installed: InstalledEntry[] = [];

    for (const dep of dependencies) {
        const url = repoUrl(dep.name);
        const tags = await listRemoteTags(url);
        const picked = pickBestTag(tags, dep.range);
        if (picked === null) {
            throw new Error(
                `No tag on ${dep.name} satisfies range "${dep.range}"`,
            );
        }
        const dest = vendoredPath(root, dep.name);
        if (await pathExists(dest)) {
            await rm(dest, { recursive: true, force: true });
        }
        await fetchInto(dep.name, picked.tag, dest);
        const integrity = await computeIntegrity(dest);
        const resolved = picked.tag.startsWith("v") ? picked.tag.slice(1) : picked.tag;
        entries.push({
            name: dep.name,
            requested: dep.range,
            resolved,
            commit: picked.commit,
            integrity,
        });
        installed.push({ name: dep.name, resolved, action: "installed" });
    }

    return { entries, installed };
}

/**
 * Clone a package at the given tag into `destination`, removing the
 * `.git` directory afterwards so the vendored tree is plain content.
 */
async function fetchInto(
    packageName: string,
    tag: string,
    destination: string,
): Promise<void> {
    await mkdir(dirname(destination), { recursive: true });
    const url = repoUrl(packageName);
    // Accept either `v1.2.3` or `1.2.3`; resolver already picked the exact tag string.
    await cloneAtRef(url, tag, destination);
    await rm(join(destination, ".git"), { recursive: true, force: true });
}

async function pathExists(path: string): Promise<boolean> {
    try {
        await access(path);
        return true;
    } catch {
        return false;
    }
}
