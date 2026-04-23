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
            requested: "^0.2.0",
            resolved: "0.2.1",
            commit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            integrity: "sha256-bbbb",
        },
        {
            name: "@a/one",
            requested: "^1.0.0",
            resolved: "1.0.3",
            commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            integrity: "sha256-aaaa",
        },
    ],
};

describe("lockfileExists", () => {
    it("returns false when absent", async () => {
        expect(await lockfileExists(join(tmp, "substrate.lock"))).toBe(false);
    });

    it("returns true when present", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, "");
        expect(await lockfileExists(path)).toBe(true);
    });
});

describe("readLockfile", () => {
    it("round-trips a written lockfile", async () => {
        const path = join(tmp, "substrate.lock");
        await writeLockfile(path, sample);
        const reloaded = await readLockfile(path);
        // The serialiser sorts by name for stable diffs.
        expect(reloaded.packages.map((p) => p.name)).toEqual(["@a/one", "@b/two"]);
        expect(reloaded.packages[0]!.resolved).toBe("1.0.3");
    });

    it("treats an empty lockfile as having no packages", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(path, "", "utf8");
        const lock = await readLockfile(path);
        expect(lock.packages).toEqual([]);
    });

    it("rejects entries missing required fields", async () => {
        const path = join(tmp, "substrate.lock");
        await writeFile(
            path,
            `[[packages]]\nname = "@a/one"\nrequested = "^1.0.0"\n`,
            "utf8",
        );
        await expect(readLockfile(path)).rejects.toThrow(/resolved/);
    });
});

describe("formatLockfile", () => {
    it("emits packages sorted by name", () => {
        const text = formatLockfile(sample);
        const firstAt = text.indexOf("@a/one");
        const secondAt = text.indexOf("@b/two");
        expect(firstAt).toBeGreaterThan(-1);
        expect(secondAt).toBeGreaterThan(firstAt);
    });
});
