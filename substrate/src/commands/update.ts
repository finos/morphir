/**
 * `substrate update [<package>]` — re-resolve a dependency (or every
 * dependency) against the latest tags or branch HEAD, rewrite the
 * lockfile, and refresh the vendored content.
 */
import { join } from "node:path";

import {
    LOCKFILE_FILE,
    locatePackage,
} from "../package/corpus.js";
import { listRemoteTags, repoUrl, resolveRefToCommit } from "../package/git.js";
import { computeIntegrity } from "../package/integrity.js";
import { lockfileExists, readLockfile, writeLockfile } from "../package/lockfile.js";
import type { LockEntry, LockInstall } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { isBranchRef, pickBestTag } from "../package/resolve.js";
import { fetchAndInstall } from "./install.js";

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

export async function update(
    startDir: string,
    packageName?: string,
): Promise<UpdateResult> {
    const pkg = await locatePackage(startDir);
    const lockPath = join(pkg.root, LOCKFILE_FILE);

    let previous: readonly LockEntry[] = [];
    if (await lockfileExists(lockPath)) {
        try {
            previous = (await readLockfile(lockPath)).packages;
        } catch {
            previous = [];
        }
    }
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

async function resolveDependency(root: string, dep: DependencySpec): Promise<LockEntry> {
    const url = repoUrl(dep.name);

    let ref: string;
    let commit: string;
    let resolved: string;

    if (isBranchRef(dep.range)) {
        const headCommit = await resolveRefToCommit(url, dep.range);
        if (headCommit === null) {
            throw new Error(`Branch "${dep.range}" not found on ${dep.name}`);
        }
        ref = dep.range;
        commit = headCommit;
        resolved = headCommit;
    } else {
        const tags = await listRemoteTags(url);
        const picked = pickBestTag(tags, dep.range);
        if (picked === null) {
            throw new Error(`No tag on ${dep.name} satisfies range "${dep.range}"`);
        }
        ref = picked.tag;
        commit = picked.commit;
        resolved = picked.tag.startsWith("v") ? picked.tag.slice(1) : picked.tag;
    }

    const subInstalls = await fetchAndInstall(dep.name, ref, root);
    const lockInstalls: LockInstall[] = [];
    for (const inst of subInstalls) {
        const integrity = await computeIntegrity(inst.dest);
        lockInstalls.push({ name: inst.installName, integrity });
    }

    return {
        name: dep.name,
        ref,
        requested: dep.range,
        resolved,
        commit,
        installs: lockInstalls,
    };
}

function replaceEntry(entries: LockEntry[], incoming: LockEntry): void {
    const idx = entries.findIndex((e) => e.name === incoming.name);
    if (idx >= 0) entries[idx] = incoming;
    else entries.push(incoming);
}
