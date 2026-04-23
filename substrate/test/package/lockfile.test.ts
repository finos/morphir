import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
    formatLockfile,
    readLockfile,
    writeLockfile,
    lockfileExists,
} from "../../src/package/lockfile.js";
import type { Lockfile } from "../../src/package/lockfile.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-lock-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

const sample: Lockfile = {
    packages: [
        {
            name: "@b/two",
            ref: "v0.2.1",
            requested: "^0.2.0",
            resolved: "0.2.1",
            commit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            installs: [
                { name: "@b/two", integrity: "sha256-bbbb" },
            ],
        },
        {
            name: "@a/one",
            ref: "v1.0.3",
            requested: "^1.0.0",
            resolved: "1.0.3",
            commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            installs: [
                { name: "@a/published-name", integrity: "sha256-aaaa" },
                { name: "@a/extra-pkg", integrity: "sha256-cccc" },
            ],
        },
    ],
};

describe("lockfileExists", () => {
    it("returns false when absent", async () => {
        expect(await lockfileExists(join(tmp, "substrate.lock"))).toBe(false);
    });

    it("returns true when present", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, "{}");
        expect(await lockfileExists(path)).toBe(true);
    });
});

describe("readLockfile", () => {
    it("round-trips a written lockfile", async () => {
        const path = join(tmp, "substrate.lock");
        await writeLockfile(path, sample);
        const reloaded = await readLockfile(path);
        // serialiser sorts by name
        expect(reloaded.packages.map((p) => p.name)).toEqual(["@a/one", "@b/two"]);
        expect(reloaded.packages[0]!.resolved).toBe("1.0.3");
        expect(reloaded.packages[0]!.ref).toBe("v1.0.3");
        expect(reloaded.packages[0]!.installs).toHaveLength(2);
        expect(reloaded.packages[0]!.installs[0]!.name).toBe("@a/published-name");
    });

    it("treats an empty packages array as having no packages", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, JSON.stringify({ packages: [] }), "utf8");
        const lock = await readLockfile(path);
        expect(lock.packages).toEqual([]);
    });

    it("treats a missing packages key as having no packages", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, "{}", "utf8");
        const lock = await readLockfile(path);
        expect(lock.packages).toEqual([]);
    });

    it("rejects entries missing required fields", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(
            path,
            JSON.stringify({
                packages: [{ name: "@a/one", ref: "v1.0.0", requested: "^1.0.0", resolved: "1.0.0", commit: "aaaa" }],
            }),
            "utf8",
        );
        await expect(readLockfile(path)).rejects.toThrow(/installs/);
    });

    it("rejects malformed JSON", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, "{ not json", "utf8");
        await expect(readLockfile(path)).rejects.toThrow(/Malformed JSON/);
    });
});

describe("formatLockfile", () => {
    it("emits valid JSON sorted by name", () => {
        const text = formatLockfile(sample);
        const parsed = JSON.parse(text) as { packages: Array<{ name: string }> };
        const names = parsed.packages.map((p) => p.name);
        expect(names).toEqual(["@a/one", "@b/two"]);
    });

    it("includes ref and installs fields", () => {
        const text = formatLockfile(sample);
        const parsed = JSON.parse(text) as {
            packages: Array<{ ref: string; installs: Array<{ name: string }> }>;
        };
        expect(parsed.packages[0]!.ref).toBe("v1.0.3");
        expect(parsed.packages[0]!.installs).toHaveLength(2);
    });
});
