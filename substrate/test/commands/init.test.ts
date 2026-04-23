import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { init } from "../../src/commands/init.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-init-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("init --yes", () => {
    it("writes substrate.json with corpus defaults", async () => {
        const result = await init(tmp, { yes: true });
        expect(result.manifest.kind).toBe("corpus");
        expect(result.manifest.name).toMatch(/^@[^/]+\/[^/]+$/);

        const raw = await readFile(join(tmp, "substrate.json"), "utf8");
        const parsed = JSON.parse(raw) as unknown;
        expect(parsed).toMatchObject({ package: { kind: "corpus" } });
    });

    it("creates the substrate/ directory", async () => {
        await init(tmp, { yes: true });
        const s = await stat(join(tmp, "substrate"));
        expect(s.isDirectory()).toBe(true);
    });

    it("aborts if substrate.json already exists", async () => {
        await writeFile(
            join(tmp, "substrate.json"),
            JSON.stringify({ package: { name: "@me/ex", kind: "corpus" } }),
            "utf8",
        );
        await expect(init(tmp, { yes: true })).rejects.toThrow(/already exists/);
    });
});
