import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative, sep } from "node:path";

import {
    listMarkdownFiles,
    locatePackage,
    vendoredPath,
} from "../../src/package/corpus.js";

let tmp: string;

async function setupCorpus(): Promise<void> {
    await writeFile(
        join(tmp, "substrate.toml"),
        `[package]\nname = "@me/example"\nkind = "corpus"\n`,
        "utf8",
    );
    await writeFile(join(tmp, "README.md"), "# Root\n", "utf8");
    await mkdir(join(tmp, "docs"), { recursive: true });
    await writeFile(join(tmp, "docs", "a.md"), "# A\n", "utf8");
    await mkdir(join(tmp, "substrate", "packages", "@org", "lib"), {
        recursive: true,
    });
    await writeFile(
        join(tmp, "substrate", "packages", "@org", "lib", "inside.md"),
        "# Inside\n",
        "utf8",
    );
    await mkdir(join(tmp, "node_modules", "pkg"), { recursive: true });
    await writeFile(join(tmp, "node_modules", "pkg", "x.md"), "# X\n", "utf8");
}

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-corpus-"));
    await setupCorpus();
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("locatePackage", () => {
    it("finds the manifest from the root", async () => {
        const located = await locatePackage(tmp);
        expect(located.root).toBe(tmp);
        expect(located.manifest.name).toBe("@me/example");
    });

    it("walks up from a subdirectory", async () => {
        const located = await locatePackage(join(tmp, "docs"));
        expect(located.root).toBe(tmp);
    });

    it("throws when no manifest exists", async () => {
        const orphan = await mkdtemp(join(tmpdir(), "substrate-orphan-"));
        try {
            await expect(locatePackage(orphan)).rejects.toThrow(/No substrate\.toml/);
        } finally {
            await rm(orphan, { recursive: true, force: true });
        }
    });
});

describe("listMarkdownFiles", () => {
    it("returns corpus-owned markdown and skips vendored packages", async () => {
        const files = await listMarkdownFiles(tmp);
        const relFiles = files.map((f) => relative(tmp, f).split(sep).join("/"));
        expect(relFiles).toContain("README.md");
        expect(relFiles).toContain("docs/a.md");
        expect(relFiles).not.toContain("substrate/packages/@org/lib/inside.md");
        expect(relFiles).not.toContain("node_modules/pkg/x.md");
    });

    it("includes vendored packages when asked", async () => {
        const files = await listMarkdownFiles(tmp, { includeVendored: true });
        const relFiles = files.map((f) => relative(tmp, f).split(sep).join("/"));
        expect(relFiles).toContain("substrate/packages/@org/lib/inside.md");
    });
});

describe("vendoredPath", () => {
    it("resolves a scoped package to its vendored location", () => {
        const p = vendoredPath("/root", "@org/lib");
        expect(relative("/root", p).split(sep).join("/")).toBe(
            "substrate/packages/@org/lib",
        );
    });

    it("rejects unscoped names", () => {
        expect(() => vendoredPath("/root", "bare")).toThrow(/Invalid scoped/);
    });
});
