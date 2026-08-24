import { describe, it, expect } from "vitest";
import { resolve } from "node:path";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root } from "mdast";
import { lintDocument } from "../../src/stages/lint.js";

const SPECS_DIR = resolve(import.meta.dirname, "../../specs");

function parse(md: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(md);
}

describe("lintDocument", () => {
    it("reports heading hierarchy jumps", () => {
        const root = parse("# Title\n\n### Skipped h2");
        const diags = lintDocument(root, "test.md");
        const jump = diags.find((d) => d.ruleId === "heading-increment");
        expect(jump).toBeDefined();
    });

    it("does not report valid heading hierarchy", () => {
        const root = parse("# Title\n\n## Section\n\n### Sub");
        const diags = lintDocument(root, "test.md");
        expect(diags.filter((d) => d.ruleId === "heading-increment")).toHaveLength(0);
    });

    it("reports missing type sections", () => {
        const root = parse("# Boolean [Type](../concepts/type.md)\n\nOverview only.");
        const diags = lintDocument(root, "test.md");
        const missing = diags.filter((d) => d.ruleId === "type-missing-section");
        expect(missing.length).toBeGreaterThan(0);
    });

    it("reports missing type-class sections", () => {
        const root = parse("# Eq [Type Class](../concepts/type-class.md)\n\nOverview only.");
        const diags = lintDocument(root, "test.md");
        const missing = diags.filter((d) => d.ruleId === "type-class-missing-section");
        expect(missing.length).toBeGreaterThan(0);
    });

    it("reports operations without markers", () => {
        const root = parse("### Foo [Operation](../concepts/operation.md)\n\nNo marker.");
        const diags = lintDocument(root, "test.md");
        expect(diags.some((d) => d.ruleId === "operation-missing-marker")).toBe(true);
    });

    it("reports operations without test cases", () => {
        const root = parse(
            "### Foo [Operation](../concepts/operation.md)\n\n_[Required](../concepts/operation.md)_\n\nDescription.",
        );
        const diags = lintDocument(root, "test.md");
        expect(diags.some((d) => d.ruleId === "operation-missing-tests")).toBe(true);
    });
});
