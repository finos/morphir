import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validate } from "../../src/commands/validate.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-validate-"));
    await writeFile(
        join(tmp, "substrate.toml"),
        `[package]\nname = "@me/ex"\nkind = "corpus"\n`,
        "utf8",
    );
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("validate", () => {
    it("passes on a corpus with resolvable links", async () => {
        await writeFile(
            join(tmp, "README.md"),
            `# Entry\n\nSee [B](b.md) and [C][ref].\n\n[ref]: b.md\n`,
            "utf8",
        );
        await writeFile(join(tmp, "b.md"), "# B\n", "utf8");

        const result = await validate(tmp);
        expect(result.fileCount).toBe(2);
        expect(result.diagnostics.filter((d) => d.severity === "error")).toEqual([]);
    });

    it("reports a broken inline link", async () => {
        await writeFile(
            join(tmp, "README.md"),
            `# Entry\n\nSee [Missing](missing.md).\n`,
            "utf8",
        );
        const result = await validate(tmp);
        const errors = result.diagnostics.filter((d) => d.severity === "error");
        expect(errors.length).toBeGreaterThan(0);
        expect(errors[0]!.message).toMatch(/Link target not found: missing\.md/);
    });

    it("reports a broken reference-style link", async () => {
        await writeFile(
            join(tmp, "README.md"),
            `# Entry\n\nSee [Missing][m].\n\n[m]: missing.md\n`,
            "utf8",
        );
        const result = await validate(tmp);
        const errors = result.diagnostics.filter((d) => d.severity === "error");
        expect(errors.length).toBeGreaterThan(0);
    });

    it("skips vendored packages when walking", async () => {
        await writeFile(join(tmp, "README.md"), "# Entry\n", "utf8");
        await mkdir(join(tmp, "substrate", "packages", "@org", "lib"), {
            recursive: true,
        });
        // A deliberately-broken file under vendored packages — must be ignored.
        await writeFile(
            join(tmp, "substrate", "packages", "@org", "lib", "bad.md"),
            "# Bad\n\n[missing](nowhere.md)\n",
            "utf8",
        );
        const result = await validate(tmp);
        expect(result.diagnostics.filter((d) => d.severity === "error")).toEqual([]);
        expect(result.fileCount).toBe(1);
    });

    it("resolves links from the corpus into a vendored package", async () => {
        await mkdir(join(tmp, "substrate", "packages", "@org", "lib"), {
            recursive: true,
        });
        await writeFile(
            join(tmp, "substrate", "packages", "@org", "lib", "concept.md"),
            "# Concept\n",
            "utf8",
        );
        await writeFile(
            join(tmp, "README.md"),
            `# Entry\n\nLinks to [concept](substrate/packages/@org/lib/concept.md).\n`,
            "utf8",
        );
        const result = await validate(tmp);
        expect(result.diagnostics.filter((d) => d.severity === "error")).toEqual([]);
    });
});
