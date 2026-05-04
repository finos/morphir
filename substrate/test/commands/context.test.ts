import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
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

    describe("--no-inline", () => {
        it("does not follow cross-file links", async () => {
            await writeFile(join(tmp, "a.md"), "# A\n\nSee [B](b.md).\n", "utf8");
            await writeFile(join(tmp, "b.md"), "# B\n\nDep body.\n", "utf8");
            const r = await context(tmp, ["a.md"], { noInline: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("# A");
            expect(r.markdown).not.toContain("# B");
            expect(r.markdown).not.toContain("Dep body.");
        });

        it("leaves links to non-included files unchanged", async () => {
            await writeFile(join(tmp, "a.md"), "# A\n\nSee [B](b.md).\n", "utf8");
            await writeFile(join(tmp, "b.md"), "# B\n", "utf8");
            const r = await context(tmp, ["a.md"], { noInline: true });
            expect(r.markdown).toContain("b.md");
            expect(r.markdown).not.toMatch(/\[B\]\(#b\)/);
        });

        it("still rewrites links between explicitly-included files", async () => {
            await writeFile(join(tmp, "a.md"), "# A\n\nSee [B](b.md).\n", "utf8");
            await writeFile(join(tmp, "b.md"), "# B\n\nContent.\n", "utf8");
            const r = await context(tmp, ["a.md", "b.md"], { noInline: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("# B");
            expect(r.markdown).toMatch(/\[B\]\(#b\)/);
        });

        it("respects a section anchor without pulling in linked files", async () => {
            await writeFile(
                join(tmp, "a.md"),
                [
                    "# A",
                    "",
                    "## Section One",
                    "",
                    "See [B](b.md).",
                    "",
                    "## Section Two",
                    "",
                    "Unrelated.",
                ].join("\n"),
                "utf8",
            );
            await writeFile(join(tmp, "b.md"), "# B\n\nDep body.\n", "utf8");
            const r = await context(tmp, ["a.md#section-one"], { noInline: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Section One");
            expect(r.markdown).not.toContain("Section Two");
            expect(r.markdown).not.toContain("Dep body.");
        });

        it("combined with --no-tree-shaking includes full files without following links", async () => {
            await writeFile(join(tmp, "a.md"), "# A\n\nSee [B](b.md).\n", "utf8");
            await writeFile(join(tmp, "b.md"), "# B\n\nDep body.\n", "utf8");
            const r = await context(tmp, ["a.md"], { noTreeShaking: true, noInline: true });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("# A");
            expect(r.markdown).not.toContain("# B");
        });
    });

    describe("--horizontal", () => {
        async function setupCorpus(): Promise<{ corpus: string; hRoot: string }> {
            const corpus = join(tmp, "corpus");
            await mkdir(corpus, { recursive: true });
            await writeFile(
                join(corpus, "substrate.json"),
                JSON.stringify({ package: { name: "test/corpus", kind: "corpus" } }),
                "utf8",
            );
            const hRoot = join(tmp, "annotations");
            await mkdir(hRoot, { recursive: true });
            await writeFile(
                join(hRoot, "substrate.json"),
                JSON.stringify({
                    package: {
                        name: "test/annotations",
                        kind: "horizontal",
                        version: "0.1.0",
                    },
                }),
                "utf8",
            );
            return { corpus, hRoot };
        }

        it("pulls in a horizontal section that reverse-links into an included corpus section", async () => {
            const { corpus, hRoot } = await setupCorpus();
            await writeFile(
                join(corpus, "spec.md"),
                [
                    "# Spec",
                    "",
                    "## Rule A",
                    "",
                    "Rule A body.",
                    "",
                    "## Rule B",
                    "",
                    "Rule B body.",
                    "",
                ].join("\n"),
                "utf8",
            );
            // Horizontal annotation references Rule A only.
            await writeFile(
                join(hRoot, "examples.md"),
                [
                    "# Examples",
                    "",
                    "## Example for A",
                    "",
                    "See [Rule A](../corpus/spec.md#rule-a).",
                    "",
                    "Example body for A.",
                    "",
                    "## Example for B",
                    "",
                    "Example body for B.",
                    "",
                ].join("\n"),
                "utf8",
            );
            const r = await context(corpus, ["spec.md#rule-a"], {
                horizontals: [hRoot],
            });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Rule A body.");
            expect(r.markdown).toContain("Example body for A.");
            // Rule B not included → its annotation should not appear either.
            expect(r.markdown).not.toContain("Example body for B.");
            expect(r.markdown).not.toContain("Rule B body.");
        });

        it("does nothing when no --horizontal flag is given", async () => {
            const { corpus, hRoot } = await setupCorpus();
            await writeFile(join(corpus, "spec.md"), "# Spec\n\nBody.\n", "utf8");
            await writeFile(
                join(hRoot, "ann.md"),
                "# Ann\n\nSee [spec](../corpus/spec.md).\n\nAnnotation body.\n",
                "utf8",
            );
            const r = await context(corpus, ["spec.md"]);
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Body.");
            expect(r.markdown).not.toContain("Annotation body.");
        });

        it("forward-traverses links from a reverse-pulled horizontal section", async () => {
            const { corpus, hRoot } = await setupCorpus();
            await writeFile(
                join(corpus, "spec.md"),
                "# Spec\n\nBody.\n",
                "utf8",
            );
            await writeFile(
                join(corpus, "extra.md"),
                "# Extra\n\nExtra body.\n",
                "utf8",
            );
            await writeFile(
                join(hRoot, "ann.md"),
                [
                    "# Ann",
                    "",
                    "## A",
                    "",
                    "Targets [spec](../corpus/spec.md) and links to [extra](../corpus/extra.md).",
                    "",
                ].join("\n"),
                "utf8",
            );
            const r = await context(corpus, ["spec.md"], { horizontals: [hRoot] });
            expect(r.errors).toEqual([]);
            // The horizontal section was reverse-pulled, then its forward
            // link to extra.md should have dragged extra.md in.
            expect(r.markdown).toContain("Extra body.");
        });

        it("follows horizontal-to-horizontal links forward without requiring opt-in for the second", async () => {
            const corpus = join(tmp, "corpus");
            await mkdir(corpus, { recursive: true });
            await writeFile(
                join(corpus, "substrate.json"),
                JSON.stringify({ package: { name: "test/corpus", kind: "corpus" } }),
                "utf8",
            );
            const h1 = join(tmp, "h1");
            await mkdir(h1, { recursive: true });
            await writeFile(
                join(h1, "substrate.json"),
                JSON.stringify({
                    package: { name: "test/h1", kind: "horizontal", version: "0.1.0" },
                }),
                "utf8",
            );
            const h2 = join(tmp, "h2");
            await mkdir(h2, { recursive: true });
            await writeFile(
                join(h2, "substrate.json"),
                JSON.stringify({
                    package: { name: "test/h2", kind: "horizontal", version: "0.1.0" },
                }),
                "utf8",
            );
            await writeFile(join(corpus, "spec.md"), "# Spec\n\nBody.\n", "utf8");
            await writeFile(
                join(h1, "ann.md"),
                "# Ann1\n\nTargets [spec](../corpus/spec.md). See [also](../h2/more.md).\n",
                "utf8",
            );
            await writeFile(join(h2, "more.md"), "# More\n\nMore body from h2.\n", "utf8");
            // Only h1 is opted in. h2 should be reachable via forward traversal.
            const r = await context(corpus, ["spec.md"], { horizontals: [h1] });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("More body from h2.");
        });

        it("errors when --horizontal points at a non-horizontal package", async () => {
            const { corpus } = await setupCorpus();
            await writeFile(join(corpus, "spec.md"), "# Spec\n", "utf8");
            const libRoot = join(tmp, "lib");
            await mkdir(libRoot, { recursive: true });
            await writeFile(
                join(libRoot, "substrate.json"),
                JSON.stringify({
                    package: { name: "test/lib", kind: "library", version: "0.1.0" },
                }),
                "utf8",
            );
            const r = await context(corpus, ["spec.md"], { horizontals: [libRoot] });
            expect(r.errors.length).toBeGreaterThan(0);
            expect(r.errors.join(" ")).toMatch(/expected "horizontal"/);
        });

        it("whole-file reverse links fire when any section of the target is included", async () => {
            const { corpus, hRoot } = await setupCorpus();
            await writeFile(
                join(corpus, "spec.md"),
                [
                    "# Spec",
                    "",
                    "## Section X",
                    "",
                    "Section X body.",
                    "",
                ].join("\n"),
                "utf8",
            );
            // Horizontal links to the whole file (no anchor).
            await writeFile(
                join(hRoot, "note.md"),
                "# Note\n\nApplies to [the spec](../corpus/spec.md).\n\nNote body.\n",
                "utf8",
            );
            const r = await context(corpus, ["spec.md#section-x"], {
                horizontals: [hRoot],
            });
            expect(r.errors).toEqual([]);
            expect(r.markdown).toContain("Section X body.");
            expect(r.markdown).toContain("Note body.");
        });
    });
});
