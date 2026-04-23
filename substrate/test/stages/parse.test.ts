import { describe, it, expect } from "vitest";
import { resolve } from "node:path";
import { parseFile } from "../../src/stages/parse.js";

const SPECS_DIR = resolve(import.meta.dirname, "../../specs");

describe("parseFile", () => {
    it("parses a valid spec file without errors", async () => {
        const { doc, diagnostics } = await parseFile(
            resolve(SPECS_DIR, "language/expressions/boolean.md"),
        );
        expect(diagnostics).toHaveLength(0);
        expect(doc).not.toBeNull();
        expect(doc!.root.children.length).toBeGreaterThan(0);
        expect(doc!.title).toBeTruthy();
    });

    it("returns an error for a non-existent file", async () => {
        const { doc, diagnostics } = await parseFile(
            resolve(SPECS_DIR, "nonexistent.md"),
        );
        expect(diagnostics.length).toBeGreaterThan(0);
        expect(diagnostics[0]!.severity).toBe("error");
    });

    it("detects the document kind for a type spec", async () => {
        const { doc } = await parseFile(
            resolve(SPECS_DIR, "language/expressions/boolean.md"),
        );
        expect(doc).not.toBeNull();
        expect(doc!.kind).toEqual({ type: "type", name: "Boolean" });
    });

    it("detects the document kind for a type-class spec", async () => {
        const { doc } = await parseFile(
            resolve(SPECS_DIR, "language/expressions/equality.md"),
        );
        expect(doc).not.toBeNull();
        expect(doc!.kind).toEqual({ type: "type-class", name: "Equality" });
    });

    it("parses the language index file", async () => {
        const { doc, diagnostics } = await parseFile(
            resolve(SPECS_DIR, "language.md"),
        );
        expect(diagnostics).toHaveLength(0);
        expect(doc).not.toBeNull();
    });
});
