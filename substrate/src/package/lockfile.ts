/**
 * Package lockfile — read and write `substrate.lock`.
 *
 * See `specs/tools/cli/packages.md` for the lockfile format.
 *
 * Format: JSON. Each entry in `packages` represents one resolved
 * dependency (identified by its repository name). A single repo may
 * install multiple sub-packages; these are listed in `installs`.
 */
import { readFile, writeFile, access } from "node:fs/promises";

/** One sub-package installed from a dependency. */
export interface LockInstall {
    /** Declared package name — used as the directory under `substrate/`. */
    readonly name: string;
    readonly integrity: string;
}

/** One resolved dependency entry in `substrate.lock`. */
export interface LockEntry {
    /** Dependency key in the consumer's manifest (repository identity). */
    readonly name: string;
    /**
     * The exact git ref that was checked out — the tag string (e.g. `v0.1.3`)
     * for semver-resolved deps, or the branch name (e.g. `main`) for
     * branch-pinned deps. Used to re-clone when reinstalling from lockfile.
     */
    readonly ref: string;
    readonly requested: string;
    /** Normalized version string for tags, or commit hash for branches. */
    readonly resolved: string;
    readonly commit: string;
    readonly installs: readonly LockInstall[];
}

/** Parsed contents of `substrate.lock`. */
export interface Lockfile {
    readonly packages: readonly LockEntry[];
}

/** Returns true when a lockfile exists at the given path. */
export async function lockfileExists(path: string): Promise<boolean> {
    try {
        await access(path);
        return true;
    } catch {
        return false;
    }
}

/**
 * Read and parse `substrate.lock` at the given path.
 *
 * Throws if the file is missing, malformed JSON, or violates the schema.
 */
export async function readLockfile(path: string): Promise<Lockfile> {
    let source: string;
    try {
        source = await readFile(path, "utf8");
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Cannot read lockfile at ${path}: ${message}`);
    }

    let parsed: unknown;
    try {
        parsed = JSON.parse(source);
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Malformed JSON in ${path}: ${message}`);
    }

    return validateLockfile(parsed, path);
}

/**
 * Serialise a lockfile to JSON, with entries sorted by name for stable diffs.
 */
export function formatLockfile(lockfile: Lockfile): string {
    const sorted = [...lockfile.packages].sort((a, b) => a.name.localeCompare(b.name));
    const doc = {
        packages: sorted.map((p) => ({
            name: p.name,
            ref: p.ref,
            requested: p.requested,
            resolved: p.resolved,
            commit: p.commit,
            installs: p.installs.map((i) => ({ name: i.name, integrity: i.integrity })),
        })),
    };
    return JSON.stringify(doc, null, 2) + "\n";
}

export async function writeLockfile(path: string, lockfile: Lockfile): Promise<void> {
    await writeFile(path, formatLockfile(lockfile), "utf8");
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateLockfile(value: unknown, path: string): Lockfile {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new Error(`${path}: expected a JSON object at document root`);
    }
    const root = value as Record<string, unknown>;

    const packagesRaw = root["packages"];
    if (packagesRaw === undefined) {
        return { packages: [] };
    }
    if (!Array.isArray(packagesRaw)) {
        throw new Error(`${path}: "packages" must be an array`);
    }

    const packages: LockEntry[] = [];
    for (const [i, entry] of packagesRaw.entries()) {
        if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
            throw new Error(`${path}: packages[${i}] must be an object`);
        }
        const e = entry as Record<string, unknown>;
        const name = requireStr(e, "name", path, i);
        const ref = requireStr(e, "ref", path, i);
        const requested = requireStr(e, "requested", path, i);
        const resolved = requireStr(e, "resolved", path, i);
        const commit = requireStr(e, "commit", path, i);
        const installs = parseInstalls(e["installs"], path, i);
        packages.push({ name, ref, requested, resolved, commit, installs });
    }
    return { packages };
}

function parseInstalls(value: unknown, path: string, idx: number): LockInstall[] {
    if (!Array.isArray(value)) {
        throw new Error(`${path}: packages[${idx}].installs must be an array`);
    }
    return value.map((item, j) => {
        if (typeof item !== "object" || item === null || Array.isArray(item)) {
            throw new Error(`${path}: packages[${idx}].installs[${j}] must be an object`);
        }
        const e = item as Record<string, unknown>;
        return {
            name: requireStr(e, "name", path, idx),
            integrity: requireStr(e, "integrity", path, idx),
        };
    });
}

function requireStr(
    entry: Record<string, unknown>,
    key: string,
    path: string,
    index: number,
): string {
    const v = entry[key];
    if (typeof v !== "string" || v.length === 0) {
        throw new Error(`${path}: packages[${index}].${key} is required and must be a non-empty string`);
    }
    return v;
}
