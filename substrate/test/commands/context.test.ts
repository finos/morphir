import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { context } from "../../src/commands/context.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-context-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("substrate context", () => {
    it("emits a single file verbatim when it has no outgoing links", async () => {
        await writeFile(join(tmp, "a.md"), "# A\n\nSome prose.\n", "utf8");
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        expect(r.markdown).toContain("# A");
        expect(r.markdown).toContain("Some prose.");
    });

    it("follows a cross-file link and orders dependencies first", async () => {
        await writeFile(
            join(tmp, "a.md"),
            "# A\n\nSee [B](b.md).\n",
            "utf8",
        );
        await writeFile(join(tmp, "b.md"), "# B\n\nDep body.\n", "utf8");
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        const bIdx = r.markdown.indexOf("# B");
        const aIdx = r.markdown.indexOf("# A");
        expect(bIdx).toBeGreaterThanOrEqual(0);
        expect(aIdx).toBeGreaterThanOrEqual(0);
        expect(bIdx).toBeLessThan(aIdx); // deps first
    });

    it("rewrites cross-file links to in-document anchors", async () => {
        await writeFile(
            join(tmp, "a.md"),
            "# A\n\nSee [B](b.md).\n",
            "utf8",
        );
        await writeFile(join(tmp, "b.md"), "# B\n", "utf8");
        const r = await context(tmp, ["a.md"]);
        expect(r.markdown).toMatch(/\[B\]\(#b\)/);
        expect(r.markdown).not.toContain("b.md");
    });

    it("tree-shakes at section granularity: unrelated siblings omitted", async () => {
        await writeFile(
            join(tmp, "a.md"),
            "# A\n\nSee [A1](a.md#a-1).\n",
            "utf8",
        );
        // Root b.md with section b-1 (referenced) and b-2 (not referenced).
        const content = [
            "# Root",
            "",
            "## A 1",
            "",
            "Body of A1.",
            "",
            "## A 2",
            "",
            "Body of A2 should NOT appear.",
            "",
        ].join("\n");
        // Actually put this in a.md; rebuild
        await writeFile(
            join(tmp, "a.md"),
            "# Roots\n\nSee [X](x.md#target).\n",
            "utf8",
        );
        await writeFile(
            join(tmp, "x.md"),
            [
                "# X",
                "",
                "Intro of X.",
                "",
                "## Sibling",
                "",
                "Sibling body should NOT appear.",
                "",
                "## Target",
                "",
                "Target body.",
                "",
                "### Child",
                "",
                "Child body.",
                "",
            ].join("\n"),
            "utf8",
        );
        void content;
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        expect(r.markdown).toContain("Target body.");
        expect(r.markdown).toContain("Child body.");
        expect(r.markdown).toContain("Intro of X.");
        expect(r.markdown).not.toContain("Sibling body");
    });

    it("reports missing section anchor on a root arg", async () => {
        await writeFile(join(tmp, "a.md"), "# A\n", "utf8");
        const r = await context(tmp, ["a.md#nope"]);
        expect(r.errors.length).toBeGreaterThan(0);
    });

    it("reports missing file on a root arg", async () => {
        const r = await context(tmp, ["does-not-exist.md"]);
        expect(r.errors.length).toBeGreaterThan(0);
    });

    it("disambiguates colliding section slugs across files", async () => {
        // Three files all named `# Title`. The root links to both others
        // explicitly, so both rewritten links must end up distinct.
        await writeFile(
            join(tmp, "a.md"),
            "# Title\n\nSee [B](b.md) and [C](c.md).\n",
            "utf8",
        );
        await writeFile(join(tmp, "b.md"), "# Title\n\nFrom B.\n", "utf8");
        await writeFile(join(tmp, "c.md"), "# Title\n\nFrom C.\n", "utf8");
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        // The two rewritten links must reference different anchors.
        const anchors = [...r.markdown.matchAll(/\]\(#([^)]+)\)/g)].map((m) => m[1]);
        expect(new Set(anchors).size).toBe(anchors.length);
        expect(r.markdown).toMatch(/#title-2/);
    });

    it("prefers a Summary section when a whole-file inclusion is requested", async () => {
        await writeFile(
            join(tmp, "a.md"),
            "# A\n\nLinks to [B](b.md).\n",
            "utf8",
        );
        await writeFile(
            join(tmp, "b.md"),
            [
                "# B",
                "",
                "Intro of B.",
                "",
                "## Summary",
                "",
                "Compact synopsis.",
                "",
                "## Details",
                "",
                "Verbose details that should NOT appear.",
                "",
            ].join("\n"),
            "utf8",
        );
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        expect(r.markdown).toContain("Compact synopsis.");
        expect(r.markdown).not.toContain("Verbose details");
    });

    it("falls back to whole-file when no Summary section exists", async () => {
        await writeFile(
            join(tmp, "a.md"),
            "# A\n\nLinks to [B](b.md).\n",
            "utf8",
        );
        await writeFile(
            join(tmp, "b.md"),
            "# B\n\n## Details\n\nAll content present.\n",
            "utf8",
        );
        const r = await context(tmp, ["a.md"]);
        expect(r.markdown).toContain("All content present.");
    });

    it("handles link cycles without infinite loop", async () => {
        await writeFile(join(tmp, "a.md"), "# A\n\n[to b](b.md)\n", "utf8");
        await writeFile(join(tmp, "b.md"), "# B\n\n[to a](a.md)\n", "utf8");
        const r = await context(tmp, ["a.md"]);
        expect(r.errors).toEqual([]);
        expect(r.markdown).toContain("# A");
        expect(r.markdown).toContain("# B");
    });

    describe("--no-tree-shaking", () => {
        it("includes the whole referenced file even when linked by anchor", async () => {
            await writeFile(
                join(tmp, "a.md"),
                "# A\n\nSee [target](x.md#target).\n",
                "utf8",
            );
            await writeFile(
                join(tmp, "x.md"),
                [
                    "# X",
                    "",
                    "## Sibling",
                    "",
                    "Sibling body should appear.",
                    "",
                    "## Target",
                    "",
                    "Target body.",
                    "",
                ].join("\n"),
                "utf8",
            );
            const r = await context(tmp, ["x.md#target"], { noTreeShaking: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Sibling body should appear.");
            expect(r.markdown).toContain("Target body.");
        });

        it("includes the whole file when linked without anchor, ignoring Summary preference", async () => {
            await writeFile(
                join(tmp, "b.md"),
                [
                    "# B",
                    "",
                    "## Summary",
                    "",
                    "Compact synopsis.",
                    "",
                    "## Details",
                    "",
                    "Verbose details that should appear with no-tree-shaking.",
                    "",
                ].join("\n"),
                "utf8",
            );
            const r = await context(tmp, ["b.md"], { noTreeShaking: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Compact synopsis.");
            expect(r.markdown).toContain("Verbose details that should appear");
        });

        it("still rewrites cross-file links as in-document anchors", async () => {
            await writeFile(
                join(tmp, "a.md"),
                "# A\n\nSee [B](b.md).\n",
                "utf8",
            );
            await writeFile(join(tmp, "b.md"), "# B\n\nContent.\n", "utf8");
            const r = await context(tmp, ["a.md"], { noTreeShaking: true });
            expect(r.markdown).toMatch(/\[B\]\(#b\)/);
            expect(r.markdown).not.toContain("b.md");
        });
    });
});
