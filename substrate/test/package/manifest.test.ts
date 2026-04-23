import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
    formatManifest,
    readManifest,
    writeManifest,
} from "../../src/package/manifest.js";
import type { Manifest } from "../../src/package/manifest.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-manifest-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("readManifest", () => {
    it("parses a corpus manifest with dependencies", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({
                package: { name: "@me/example", kind: "corpus" },
                dependencies: { "@AttilaMihaly/morphir-substrate": "^0.1.0" },
            }, null, 2),
            "utf8",
        );
        const manifest = await readManifest(path);
        expect(manifest.name).toBe("@me/example");
        expect(manifest.kind).toBe("corpus");
        expect(manifest.version).toBeUndefined();
        expect(manifest.dependencies).toEqual([
            { name: "@AttilaMihaly/morphir-substrate", range: "^0.1.0" },
        ]);
    });

    it("parses a library manifest with version", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({ package: { name: "@org/lib", kind: "library", version: "1.2.3" } }),
            "utf8",
        );
        const manifest = await readManifest(path);
        expect(manifest.kind).toBe("library");
        expect(manifest.version).toBe("1.2.3");
        expect(manifest.dependencies).toEqual([]);
    });

    it("rejects a library missing version", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({ package: { name: "@org/lib", kind: "library" } }),
            "utf8",
        );
        await expect(readManifest(path)).rejects.toThrow(/must declare package\.version/);
    });

    it("rejects an invalid kind", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({ package: { name: "@org/lib", kind: "application" } }),
            "utf8",
        );
        await expect(readManifest(path)).rejects.toThrow(/kind must be/);
    });

    it("rejects a non-scoped name", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({ package: { name: "bare", kind: "corpus" } }),
            "utf8",
        );
        await expect(readManifest(path)).rejects.toThrow(/@<scope>\/<name>/);
    });

    it("parses a library manifest with subdir", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(
            path,
            JSON.stringify({
                package: { name: "@org/lib", kind: "library", version: "1.0.0", subdir: "specs" },
            }),
            "utf8",
        );
        const manifest = await readManifest(path);
        expect(manifest.subdir).toBe("specs");
    });

    it("rejects malformed JSON", async () => {
        const path = join(tmp, "substrate.json");
        await writeFile(path, `{ not valid json`, "utf8");
        await expect(readManifest(path)).rejects.toThrow(/Malformed JSON/);
    });
});

describe("formatManifest / writeManifest round-trip", () => {
    it("preserves all declared fields", async () => {
        const path = join(tmp, "substrate.json");
        const manifest: Manifest = {
            name: "@me/example",
            kind: "library",
            version: "0.1.0",
            dependencies: [
                { name: "@a/one", range: "^1.0.0" },
                { name: "@b/two", range: "~0.2.0" },
            ],
        };
        await writeManifest(path, manifest);
        const reloaded = await readManifest(path);
        expect(reloaded).toEqual(manifest);
    });

    it("round-trips a manifest with subdir", async () => {
        const path = join(tmp, "substrate.json");
        const manifest: Manifest = {
            name: "@org/lib",
            kind: "library",
            version: "1.0.0",
            subdir: "specs",
            dependencies: [],
        };
        await writeManifest(path, manifest);
        const reloaded = await readManifest(path);
        expect(reloaded.subdir).toBe("specs");
    });

    it("omits the dependencies key when empty", () => {
        const manifest: Manifest = {
            name: "@me/solo",
            kind: "library",
            version: "0.1.0",
            dependencies: [],
        };
        const text = formatManifest(manifest);
        expect(text).not.toMatch(/"dependencies"/);
    });
});
