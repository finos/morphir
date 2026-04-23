/**
 * `substrate update [<package>]` — re-resolve a dependency (or every
 * dependency) against the latest tags or branch HEAD, rewrite the
 * lockfile, and refresh the vendored content.
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
import type { LockEntry } from "../package/lockfile.js";
import type { DependencySpec } from "../package/manifest.js";
import { readManifest } from "../package/manifest.js";
import { isBranchRef, pickBestTag } from "../package/resolve.js";

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

    const { installName, dest } = await fetchAndInstall(dep.name, ref, root);
    const integrity = await computeIntegrity(dest);

    return {
        name: dep.name,
        installName,
        requested: dep.range,
        resolved,
        commit,
        integrity,
    };
}

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

function replaceEntry(entries: LockEntry[], incoming: LockEntry): void {
    const idx = entries.findIndex((e) => e.name === incoming.name);
    if (idx >= 0) entries[idx] = incoming;
    else entries.push(incoming);
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
