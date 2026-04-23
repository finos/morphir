import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { computeIntegrity } from "../../src/package/integrity.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-integrity-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("computeIntegrity", () => {
    it("is stable across invocations on the same content", async () => {
        await writeFile(join(tmp, "a.md"), "alpha\n", "utf8");
        await writeFile(join(tmp, "b.md"), "beta\n", "utf8");
        const first = await computeIntegrity(tmp);
        const second = await computeIntegrity(tmp);
        expect(first).toBe(second);
        expect(first).toMatch(/^sha256-/);
    });

    it("changes when file contents change", async () => {
        await writeFile(join(tmp, "a.md"), "alpha\n", "utf8");
        const before = await computeIntegrity(tmp);
        await writeFile(join(tmp, "a.md"), "alphaX\n", "utf8");
        const after = await computeIntegrity(tmp);
        expect(after).not.toBe(before);
    });

    it("ignores the .git directory", async () => {
        await writeFile(join(tmp, "a.md"), "alpha\n", "utf8");
        const before = await computeIntegrity(tmp);
        await mkdir(join(tmp, ".git"), { recursive: true });
        await writeFile(join(tmp, ".git", "HEAD"), "ref: refs/heads/main\n", "utf8");
        const after = await computeIntegrity(tmp);
        expect(after).toBe(before);
    });
});
