import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { publish } from "../../src/commands/publish.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-publish-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("publish", () => {
    it("aborts on a corpus package before touching git", async () => {
        await writeFile(
            join(tmp, "substrate.json"),
            JSON.stringify({ package: { name: "me/ex", kind: "corpus" } }),
            "utf8",
        );
        await expect(publish(tmp)).rejects.toThrow(/Cannot publish corpus/);
    });

    it("aborts on a library missing version", async () => {
        // The manifest reader itself rejects a library without a version;
        // surface that as the pre-git failure mode.
        await writeFile(
            join(tmp, "substrate.json"),
            JSON.stringify({ package: { name: "me/lib", kind: "library" } }),
            "utf8",
        );
        await expect(publish(tmp)).rejects.toThrow(/version/);
    });
});
