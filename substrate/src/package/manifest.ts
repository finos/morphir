/**
 * Package manifest — read and write `substrate.toml`.
 *
 * See `specs/tools/packages.md` for the manifest format.
 */
import { readFile, writeFile } from "node:fs/promises";
import { parse as parseToml, stringify as stringifyToml } from "smol-toml";

/** Kind declared in `[package].kind`. */
export type PackageKind = "library" | "corpus";

/** A single dependency entry: a scoped name and a semver range. */
export interface DependencySpec {
    readonly name: string;
    readonly range: string;
}

/** Parsed contents of `substrate.toml`. */
export interface Manifest {
    readonly name: string;
    readonly kind: PackageKind;
    /** Present for libraries; typically absent for corpora. */
    readonly version?: string;
    readonly dependencies: readonly DependencySpec[];
}

/**
 * Read and parse `substrate.toml` at the given path.
 *
 * Throws if the file is missing, malformed TOML, or violates the
 * manifest schema (missing required fields, unknown kind, etc.).
 */
export async function readManifest(path: string): Promise<Manifest> {
    let source: string;
    try {
        source = await readFile(path, "utf8");
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Cannot read manifest at ${path}: ${message}`);
    }

    let parsed: unknown;
    try {
        parsed = parseToml(source);
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Malformed TOML in ${path}: ${message}`);
    }

    return validateManifest(parsed, path);
}

/**
 * Serialise a manifest back to TOML.
 *
 * Emits the canonical key order: `[package]` first with `name`, `kind`,
 * `version` (if present), then `[dependencies]`.
 */
export function formatManifest(manifest: Manifest): string {
    const pkg: Record<string, string> = {
        name: manifest.name,
        kind: manifest.kind,
    };
    if (manifest.version !== undefined) {
        pkg["version"] = manifest.version;
    }

    const deps: Record<string, string> = {};
    for (const dep of manifest.dependencies) {
        deps[dep.name] = dep.range;
    }

    const doc: Record<string, unknown> = { package: pkg };
    if (manifest.dependencies.length > 0) {
        doc["dependencies"] = deps;
    }

    return stringifyToml(doc);
}

export async function writeManifest(path: string, manifest: Manifest): Promise<void> {
    await writeFile(path, formatManifest(manifest), "utf8");
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateManifest(value: unknown, path: string): Manifest {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new Error(`${path}: expected a TOML table at document root`);
    }
    const root = value as Record<string, unknown>;

    const pkgRaw = root["package"];
    if (typeof pkgRaw !== "object" || pkgRaw === null || Array.isArray(pkgRaw)) {
        throw new Error(`${path}: missing [package] table`);
    }
    const pkg = pkgRaw as Record<string, unknown>;

    const name = pkg["name"];
    if (typeof name !== "string" || name.length === 0) {
        throw new Error(`${path}: [package].name is required and must be a string`);
    }
    if (!/^@[^/]+\/[^/]+$/.test(name)) {
        throw new Error(`${path}: [package].name must match "@<scope>/<name>", got "${name}"`);
    }

    const kindRaw = pkg["kind"];
    if (kindRaw !== "library" && kindRaw !== "corpus") {
        throw new Error(`${path}: [package].kind must be "library" or "corpus"`);
    }
    const kind: PackageKind = kindRaw;

    let version: string | undefined;
    if (pkg["version"] !== undefined) {
        if (typeof pkg["version"] !== "string") {
            throw new Error(`${path}: [package].version must be a string`);
        }
        version = pkg["version"];
    }
    if (kind === "library" && version === undefined) {
        throw new Error(`${path}: library packages must declare [package].version`);
    }

    const depsRaw = root["dependencies"];
    const dependencies: DependencySpec[] = [];
    if (depsRaw !== undefined) {
        if (typeof depsRaw !== "object" || depsRaw === null || Array.isArray(depsRaw)) {
            throw new Error(`${path}: [dependencies] must be a table`);
        }
        for (const [depName, depValue] of Object.entries(depsRaw as Record<string, unknown>)) {
            if (typeof depValue !== "string") {
                throw new Error(
                    `${path}: dependency "${depName}" must be a semver-range string`,
                );
            }
            if (!/^@[^/]+\/[^/]+$/.test(depName)) {
                throw new Error(
                    `${path}: dependency name must match "@<scope>/<name>", got "${depName}"`,
                );
            }
            dependencies.push({ name: depName, range: depValue });
        }
    }

    return version !== undefined
        ? { name, kind, version, dependencies }
        : { name, kind, dependencies };
}
