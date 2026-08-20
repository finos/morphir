import { describe, it, expect } from "vitest";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root } from "mdast";
import { composeContext } from "../../src/stages/context.js";

const SPECS_ROOT = resolve(
    fileURLToPath(new URL(".", import.meta.url)),
    "../../specs/language/expressions",
);

function emptyRoot(): Root {
    return unified().use(remarkParse).use(remarkGfm).parse("") as Root;
}

describe("composeContext", () => {
    it(
        "returns a non-empty composed root for a real spec file",
        async () => {
            const file = resolve(SPECS_ROOT, "boolean.md");
            const { diagnostics, data } = await composeContext(file, emptyRoot());
            const errors = diagnostics.filter((d) => d.severity === "error");
            expect(errors, `context errors: ${errors.map(d => d.message).join("; ")}`).toHaveLength(0);
            expect(data).not.toBeNull();
            expect(data!.children.length).toBeGreaterThan(0);
        },
        10_000,
    );

    it(
        "returns error diagnostics and null data for a nonexistent file",
        async () => {
            const file = resolve(SPECS_ROOT, "nonexistent-file-xyz.md");
            const { diagnostics, data } = await composeContext(file, emptyRoot());
            expect(data).toBeNull();
            expect(diagnostics.some((d) => d.severity === "error")).toBe(true);
        },
        10_000,
    );

    it(
        "composed root contains content from linked files",
        async () => {
            const file = resolve(SPECS_ROOT, "boolean.md");
            const { diagnostics, data } = await composeContext(file, emptyRoot());
            const errors = diagnostics.filter((d) => d.severity === "error");
            expect(errors, `context errors: ${errors.map(d => d.message).join("; ")}`).toHaveLength(0);
            expect(data).not.toBeNull();
            expect(data!.children.length).toBeGreaterThan(5);
        },
        10_000,
    );
});
