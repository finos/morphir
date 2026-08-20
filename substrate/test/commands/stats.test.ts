import { describe, it, expect } from "vitest";
import { computeStats } from "../../src/commands/stats.js";

describe("substrate stats", () => {
    it("counts words, lines, and estimates tokens", () => {
        const source = "# Hello\n\nThis is a test.\n";
        const r = computeStats(source);
        expect(r.wordCount).toBe(5); // Hello, This, is, a, test.
        expect(r.lineCount).toBe(4); // "# Hello", "", "This is a test.", ""
        expect(r.tokenEstimate).toBe(Math.ceil(source.length / 4));
    });

    it("excludes code block content from word count", () => {
        const source = "# Title\n\nProse here.\n\n```\ncode not counted\n```\n";
        const r = computeStats(source);
        expect(r.wordCount).toBe(3); // Title, Prose, here.
    });

    it("excludes inline code from word count", () => {
        const source = "Use `foo` carefully.\n";
        const r = computeStats(source);
        expect(r.wordCount).toBe(2); // Use, carefully.
    });

    it("classifies links as external, local, and anchors", () => {
        const source = [
            "# Test",
            "",
            "[ext1](https://example.com)",
            "[ext2](http://other.org)",
            "[local](other.md)",
            "[anchor](#heading)",
            "[mailto](mailto:a@b.com)",
            "",
        ].join("\n");
        const r = computeStats(source);
        expect(r.links.external).toBe(3); // https, http, mailto
        expect(r.links.local).toBe(1);
        expect(r.links.anchors).toBe(1);
    });

    it("counts reference-style link definitions", () => {
        const source = "# T\n\n[link][ref]\n\n[ref]: https://example.com\n";
        const r = computeStats(source);
        expect(r.links.external).toBe(1); // definition URL counts
    });

    it("counts sections and computes header depth stats", () => {
        const source = "# H1\n\n## H2a\n\n## H2b\n\n### H3\n";
        const r = computeStats(source);
        expect(r.sectionCount).toBe(4);
        expect(r.maxHeaderDepth).toBe(3);
        // (1 + 2 + 2 + 3) / 4 = 2.0
        expect(r.avgHeaderDepth).toBeCloseTo(2.0);
    });

    it("returns zeros for empty input", () => {
        const r = computeStats("");
        expect(r.wordCount).toBe(0);
        expect(r.sectionCount).toBe(0);
        expect(r.maxHeaderDepth).toBe(0);
        expect(r.avgHeaderDepth).toBe(0);
        expect(r.links.external).toBe(0);
        expect(r.links.local).toBe(0);
        expect(r.links.anchors).toBe(0);
    });
});
