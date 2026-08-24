/**
 * Package manifest — read and write `substrate.json`.
 *
 * See `specs/tools/cli/packages.md` for the manifest format.
 */
import { readFile, writeFile } from "node:fs/promises";

/** Kind declared in `package.kind`. */
export type PackageKind = "library" | "corpus" | "horizontal";

/** A single dependency entry: a scoped name and a semver range or branch. */
export interface DependencySpec {
    readonly name: string;
    readonly range: string;
}

/** Parsed contents of `substrate.json`. */
export interface Manifest {
    readonly name: string;
    readonly kind: PackageKind;
    /** Present for libraries; typically absent for corpora. */
    readonly version?: string;
    /**
     * Optional sub-directory within the repository where the substrate
     * documents reside. When set, `substrate install` extracts only this
     * directory's contents into the vendored location.
     */
    readonly subdir?: string;
    readonly dependencies: readonly DependencySpec[];
}

/**
 * Read and parse `substrate.json` at the given path.
 *
 * Throws if the file is missing, malformed JSON, or violates the
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
        parsed = JSON.parse(source);
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        throw new Error(`Malformed JSON in ${path}: ${message}`);
    }

    return validateManifest(parsed, path);
}

/**
 * Serialise a manifest to JSON.
 *
 * Emits the canonical key order: `package` first with `name`, `kind`,
 * `version` (if present), `subdir` (if present), then `dependencies`.
 */
export function formatManifest(manifest: Manifest): string {
    const pkg: Record<string, string> = {
        name: manifest.name,
        kind: manifest.kind,
    };
    if (manifest.version !== undefined) {
        pkg["version"] = manifest.version;
    }
    if (manifest.subdir !== undefined) {
        pkg["subdir"] = manifest.subdir;
    }

    const deps: Record<string, string> = {};
    for (const dep of manifest.dependencies) {
        deps[dep.name] = dep.range;
    }

    const doc: Record<string, unknown> = { package: pkg };
    if (manifest.dependencies.length > 0) {
        doc["dependencies"] = deps;
    }

    return JSON.stringify(doc, null, 2) + "\n";
}

export async function writeManifest(path: string, manifest: Manifest): Promise<void> {
    await writeFile(path, formatManifest(manifest), "utf8");
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateManifest(value: unknown, path: string): Manifest {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new Error(`${path}: expected a JSON object at document root`);
    }
    const root = value as Record<string, unknown>;

    const pkgRaw = root["package"];
    if (typeof pkgRaw !== "object" || pkgRaw === null || Array.isArray(pkgRaw)) {
        throw new Error(`${path}: missing "package" object`);
    }
    const pkg = pkgRaw as Record<string, unknown>;

    const name = pkg["name"];
    if (typeof name !== "string" || name.length === 0) {
        throw new Error(`${path}: package.name is required and must be a string`);
    }
    if (!isValidPackagePath(name)) {
        throw new Error(
            `${path}: package.name must be a non-empty path with no leading/trailing ` +
                `slashes or ".." segments, got "${name}"`,
        );
    }

    const kindRaw = pkg["kind"];
    if (kindRaw !== "library" && kindRaw !== "corpus" && kindRaw !== "horizontal") {
        throw new Error(
            `${path}: package.kind must be "library", "corpus", or "horizontal"`,
        );
    }
    const kind: PackageKind = kindRaw;

    let version: string | undefined;
    if (pkg["version"] !== undefined) {
        if (typeof pkg["version"] !== "string") {
            throw new Error(`${path}: package.version must be a string`);
        }
        version = pkg["version"];
    }
    if ((kind === "library" || kind === "horizontal") && version === undefined) {
        throw new Error(
            `${path}: ${kind} packages must declare package.version`,
        );
    }

    let subdir: string | undefined;
    if (pkg["subdir"] !== undefined) {
        if (typeof pkg["subdir"] !== "string" || pkg["subdir"].length === 0) {
            throw new Error(`${path}: package.subdir must be a non-empty string`);
        }
        subdir = pkg["subdir"];
    }

    const depsRaw = root["dependencies"];
    const dependencies: DependencySpec[] = [];
    if (depsRaw !== undefined) {
        if (typeof depsRaw !== "object" || depsRaw === null || Array.isArray(depsRaw)) {
            throw new Error(`${path}: "dependencies" must be an object`);
        }
        for (const [depName, depValue] of Object.entries(depsRaw as Record<string, unknown>)) {
            if (typeof depValue !== "string") {
                throw new Error(
                    `${path}: dependency "${depName}" must be a semver-range or branch string`,
                );
            }
            if (!isValidPackagePath(depName)) {
                throw new Error(
                    `${path}: dependency name must be a non-empty path with no leading/trailing ` +
                        `slashes or ".." segments, got "${depName}"`,
                );
            }
            dependencies.push({ name: depName, range: depValue });
        }
    }

    const result: Record<string, unknown> = { name, kind, dependencies };

    if (version !== undefined) result["version"] = version;
    if (subdir !== undefined) result["subdir"] = subdir;

    return result as unknown as Manifest;
}

/**
 * Returns true when `name` is a valid package path: non-empty, no leading
 * or trailing slashes, no empty segments, and no ".." segments (to prevent
 * path traversal).
 */
export function isValidPackagePath(name: string): boolean {
    if (name.length === 0) return false;
    if (name.startsWith("/") || name.endsWith("/")) return false;
    const segments = name.split("/");
    return segments.every((seg) => seg.length > 0 && seg !== "..");
}
