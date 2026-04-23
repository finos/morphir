/**
 * Package lockfile — read and write `substrate.lock`.
 *
 * See `specs/tools/packages.md` for the lockfile format.
 */
import { readFile, writeFile, access } from "node:fs/promises";
import { parse as parseToml, stringify as stringifyToml } from "smol-toml";

/** One resolved dependency entry in `substrate.lock`. */
export interface LockEntry {
    readonly name: string;
    readonly requested: string;
    readonly resolved: string;
    readonly commit: string;
    readonly integrity: string;
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
 * Throws if the file is missing, malformed, or violates the schema.
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
        parsed = parseToml(source);
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Malformed TOML in ${path}: ${message}`);
    }

    return validateLockfile(parsed, path);
}

/**
 * Serialise a lockfile back to TOML using the canonical `[[packages]]`
 * array-of-tables form, with entries sorted by name for stable diffs.
 */
export function formatLockfile(lockfile: Lockfile): string {
    const sorted = [...lockfile.packages].sort((a, b) => a.name.localeCompare(b.name));
    const doc = {
        packages: sorted.map((p) => ({
            name: p.name,
            requested: p.requested,
            resolved: p.resolved,
            commit: p.commit,
            integrity: p.integrity,
        })),
    };
    return stringifyToml(doc);
}

export async function writeLockfile(path: string, lockfile: Lockfile): Promise<void> {
    await writeFile(path, formatLockfile(lockfile), "utf8");
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateLockfile(value: unknown, path: string): Lockfile {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new Error(`${path}: expected a TOML table at document root`);
    }
    const root = value as Record<string, unknown>;

    const packagesRaw = root["packages"];
    if (packagesRaw === undefined) {
        return { packages: [] };
    }
    if (!Array.isArray(packagesRaw)) {
        throw new Error(`${path}: [[packages]] must be an array of tables`);
    }

    const packages: LockEntry[] = [];
    for (const [i, entry] of packagesRaw.entries()) {
        if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
            throw new Error(`${path}: packages[${i}] must be a table`);
        }
        const e = entry as Record<string, unknown>;
        packages.push({
            name: requireString(e, "name", path, i),
            requested: requireString(e, "requested", path, i),
            resolved: requireString(e, "resolved", path, i),
            commit: requireString(e, "commit", path, i),
            integrity: requireString(e, "integrity", path, i),
        });
    }
    return { packages };
}

function requireString(
    entry: Record<string, unknown>,
    key: string,
    path: string,
    index: number,
): string {
    const v = entry[key];
    if (typeof v !== "string" || v.length === 0) {
        throw new Error(`${path}: packages[${index}].${key} is required and must be a string`);
    }
    return v;
}
