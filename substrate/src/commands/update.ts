/**
 * `substrate update [<package>]` — re-resolve a dependency (or every
 * dependency) against the latest tags, rewrite the lockfile, and
 * refresh the vendored content.
 */
import { rm } from "node:fs/promises";
import { join } from "node:path";

import {
    LOCKFILE_FILE,
    locatePackage,
    vendoredPath,
} from "../package/corpus.js";
import { listRemoteTags, repoUrl } from "../package/git.js";
import { computeIntegrity } from "../package/integrity.js";
import {
    lockfileExists,
    readLockfile,
    writeLockfile,
} from "../package/lockfile.js";
import type { LockEntry } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { pickBestTag } from "../package/resolve.js";
import { cloneAtRef } from "../package/git.js";
import { mkdir, access } from "node:fs/promises";
import { dirname } from "node:path";

export interface UpdateResult {
    readonly root: string;
    readonly updated: readonly UpdatedEntry[];
}

export interface UpdatedEntry {
    readonly name: string;
    readonly from: string | null;
    readonly to: string;
    readonly changed: boolean;
}

/**
 * Update one named package, or every dependency when `packageName` is
 * undefined.
 */
export async function update(
    startDir: string,
    packageName?: string,
): Promise<UpdateResult> {
    const pkg = await locatePackage(startDir);
    const lockPath = join(pkg.root, LOCKFILE_FILE);

    const previous = (await lockfileExists(lockPath))
        ? (await readLockfile(lockPath)).packages
        : [];
    const previousByName = new Map(previous.map((p) => [p.name, p]));

    const targets =
        packageName === undefined
            ? pkg.manifest.dependencies
            : pkg.manifest.dependencies.filter((d) => d.name === packageName);

    if (packageName !== undefined && targets.length === 0) {
        throw new Error(`Package "${packageName}" is not a declared dependency`);
    }

    const updated: UpdatedEntry[] = [];
    const newEntries: LockEntry[] = [...previous];

    for (const dep of targets) {
        const entry = await resolveDependency(pkg.root, dep);
        const prior = previousByName.get(dep.name);
        const changed = prior === undefined || prior.resolved !== entry.resolved;
        replaceEntry(newEntries, entry);
        updated.push({
            name: dep.name,
            from: prior?.resolved ?? null,
            to: entry.resolved,
            changed,
        });
    }

    await writeLockfile(lockPath, { packages: newEntries });
    return { root: pkg.root, updated };
}

async function resolveDependency(
    root: string,
    dep: DependencySpec,
): Promise<LockEntry> {
    const url = repoUrl(dep.name);
    const tags = await listRemoteTags(url);
    const picked = pickBestTag(tags, dep.range);
    if (picked === null) {
        throw new Error(`No tag on ${dep.name} satisfies range "${dep.range}"`);
    }
    const dest = vendoredPath(root, dep.name);
    if (await pathExists(dest)) {
        await rm(dest, { recursive: true, force: true });
    }
    await mkdir(dirname(dest), { recursive: true });
    await cloneAtRef(url, picked.tag, dest);
    await rm(join(dest, ".git"), { recursive: true, force: true });
    const integrity = await computeIntegrity(dest);
    const resolved = picked.tag.startsWith("v") ? picked.tag.slice(1) : picked.tag;
    return {
        name: dep.name,
        requested: dep.range,
        resolved,
        commit: picked.commit,
        integrity,
    };
}

function replaceEntry(entries: LockEntry[], incoming: LockEntry): void {
    const idx = entries.findIndex((e) => e.name === incoming.name);
    if (idx >= 0) entries[idx] = incoming;
    else entries.push(incoming);
}

async function pathExists(path: string): Promise<boolean> {
    try {
        await access(path);
        return true;
    } catch {
        return false;
    }
}
