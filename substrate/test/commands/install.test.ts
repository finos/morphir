import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { scanManifests } from "../../src/commands/install.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-install-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

async function writeManifest(dir: string, name: string, subdir?: string): Promise<void> {
    const pkg: Record<string, string> = { name, kind: "library", version: "0.1.0" };
    if (subdir) pkg["subdir"] = subdir;
    await writeFile(join(dir, "substrate.json"), JSON.stringify({ package: pkg }), "utf8");
}

describe("scanManifests", () => {
    it("finds a single manifest at the root", async () => {
        await writeManifest(tmp, "@org/root");
        const pkgs = await scanManifests(tmp);
        expect(pkgs).toHaveLength(1);
        expect(pkgs[0]!.installName).toBe("@org/root");
        expect(pkgs[0]!.sourceDir).toBe(tmp);
    });

    it("finds manifests in sub-directories", async () => {
        await mkdir(join(tmp, "sub"), { recursive: true });
        await writeManifest(tmp, "@org/root");
        await writeManifest(join(tmp, "sub"), "@org/sub");
        const pkgs = await scanManifests(tmp);
        const names = pkgs.map((p) => p.installName).sort();
        expect(names).toEqual(["@org/root", "@org/sub"]);
    });

    it("resolves sourceDir to subdir when specified", async () => {
        await mkdir(join(tmp, "specs"), { recursive: true });
        await writeManifest(tmp, "@org/lib", "specs");
        const pkgs = await scanManifests(tmp);
        expect(pkgs[0]!.sourceDir).toBe(join(tmp, "specs"));
    });

    it("skips the substrate/ vendor directory", async () => {
        await mkdir(join(tmp, "substrate", "@other", "pkg"), { recursive: true });
        await writeManifest(tmp, "@org/root");
        await writeManifest(join(tmp, "substrate", "@other", "pkg"), "@other/pkg");
        const pkgs = await scanManifests(tmp);
        expect(pkgs).toHaveLength(1);
        expect(pkgs[0]!.installName).toBe("@org/root");
    });

    it("skips node_modules and .git", async () => {
        await mkdir(join(tmp, "node_modules", "@x", "y"), { recursive: true });
        await mkdir(join(tmp, ".git", "hooks"), { recursive: true });
        await writeManifest(tmp, "@org/root");
        await writeManifest(join(tmp, "node_modules", "@x", "y"), "@x/y");
        await writeManifest(join(tmp, ".git", "hooks"), "@bad/hook");
        const pkgs = await scanManifests(tmp);
        expect(pkgs).toHaveLength(1);
    });

    it("returns empty array when no manifests exist", async () => {
        const pkgs = await scanManifests(tmp);
        expect(pkgs).toEqual([]);
    });

    it("silently skips manifests with invalid content", async () => {
        await writeFile(join(tmp, "substrate.json"), "{ invalid json", "utf8");
        const pkgs = await scanManifests(tmp);
        expect(pkgs).toEqual([]);
    });
});
