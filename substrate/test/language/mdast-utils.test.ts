import { describe, it, expect } from "vitest";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, Heading } from "mdast";
import {
    nodeText,
    isHeading,
    detectConceptLink,
    headingName,
    inclusionTarget,
    slugify,
    isTable,
    isList,
    tableHeaders,
    rowCells,
    parseCellValue,
    collectLinks,
    collectAnchors,
} from "../../src/language/mdast-utils.js";

function parse(md: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(md);
}

function firstHeading(root: Root): Heading {
    const h = root.children.find((n) => n.type === "heading");
    if (!h || h.type !== "heading") throw new Error("no heading found");
    return h as Heading;
}

// ---------------------------------------------------------------------------
// nodeText
// ---------------------------------------------------------------------------

describe("nodeText", () => {
    it("extracts plain text from a paragraph", () => {
        const root = parse("Hello **world**");
        expect(nodeText(root.children[0]!)).toBe("Hello world");
    });

    it("extracts text from inline code", () => {
        const root = parse("Use `true` here");
        expect(nodeText(root.children[0]!)).toBe("Use true here");
    });

    it("returns empty string for null/undefined", () => {
        expect(nodeText(null)).toBe("");
        expect(nodeText(undefined)).toBe("");
    });
});

// ---------------------------------------------------------------------------
// isHeading
// ---------------------------------------------------------------------------

describe("isHeading", () => {
    it("returns true for heading nodes", () => {
        const root = parse("## Sub");
        expect(isHeading(root.children[0]!)).toBe(true);
    });

    it("returns false for paragraph nodes", () => {
        const root = parse("text");
        expect(isHeading(root.children[0]!)).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// detectConceptLink
// ---------------------------------------------------------------------------

describe("detectConceptLink", () => {
    it("detects a type concept link", () => {
        const root = parse("# Boolean [Type](../concepts/type.md)");
        expect(detectConceptLink(firstHeading(root))).toBe("type");
    });

    it("detects a type-class concept link", () => {
        const root = parse("# Equality [Type Class](../concepts/type-class.md)");
        expect(detectConceptLink(firstHeading(root))).toBe("type-class");
    });

    it("returns null when no concept link is present", () => {
        const root = parse("# Plain Heading");
        expect(detectConceptLink(firstHeading(root))).toBeNull();
    });

    it("returns null for an external link", () => {
        const root = parse("# Thing [Link](https://example.com)");
        expect(detectConceptLink(firstHeading(root))).toBeNull();
    });
});

// ---------------------------------------------------------------------------
// headingName
// ---------------------------------------------------------------------------

describe("headingName", () => {
    it("extracts the name before the concept link", () => {
        const root = parse("# Boolean [Type](../concepts/type.md)");
        expect(headingName(firstHeading(root))).toBe("Boolean");
    });

    it("returns full text when no concept link", () => {
        const root = parse("## Member Values");
        expect(headingName(firstHeading(root))).toBe("Member Values");
    });
});

// ---------------------------------------------------------------------------
// inclusionTarget
// ---------------------------------------------------------------------------

describe("inclusionTarget", () => {
    it("returns URL when heading is a single link", () => {
        const root = parse("## [Boolean](expressions/boolean.md)");
        expect(inclusionTarget(firstHeading(root))).toBe("expressions/boolean.md");
    });

    it("returns null when heading has text besides the link", () => {
        const root = parse("## Prefix [Boolean](expressions/boolean.md)");
        expect(inclusionTarget(firstHeading(root))).toBeNull();
    });

    it("returns null for a plain heading", () => {
        const root = parse("## Overview");
        expect(inclusionTarget(firstHeading(root))).toBeNull();
    });
});

// ---------------------------------------------------------------------------
// slugify
// ---------------------------------------------------------------------------

describe("slugify", () => {
    it("lowercases and replaces spaces", () => {
        expect(slugify("Member Values")).toBe("member-values");
    });

    it("strips special characters", () => {
        expect(slugify("Not Operation (!)")).toBe("not-operation");
    });

    it("collapses consecutive hyphens", () => {
        expect(slugify("A -- B")).toBe("a-b");
    });
});

// ---------------------------------------------------------------------------
// parseCellValue
// ---------------------------------------------------------------------------

describe("parseCellValue", () => {
    it("parses true", () => {
        expect(parseCellValue("true")).toBe(true);
    });

    it("parses false", () => {
        expect(parseCellValue("false")).toBe(false);
    });

    it("parses integers", () => {
        expect(parseCellValue("42")).toBe(42);
    });

    it("parses negative floats", () => {
        expect(parseCellValue("-3.14")).toBe(-3.14);
    });

    it("returns strings for non-numeric text", () => {
        expect(parseCellValue("hello")).toBe("hello");
    });

    it("returns empty string as string, not number", () => {
        expect(parseCellValue("")).toBe("");
    });
});

// ---------------------------------------------------------------------------
// Table helpers
// ---------------------------------------------------------------------------

describe("tableHeaders", () => {
    it("extracts headers from a GFM table", () => {
        const root = parse("| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |");
        const table = root.children.find((n) => n.type === "table");
        expect(table).toBeDefined();
        expect(tableHeaders(table as any)).toEqual(["A", "B", "C"]);
    });
});

describe("rowCells", () => {
    it("extracts cell text from a row", () => {
        const root = parse("| A | B |\n|---|---|\n| `true` | `false` |");
        const table = root.children.find((n) => n.type === "table") as any;
        // Row 1 is the data row (row 0 is headers)
        const cells = rowCells(table.children[1]);
        expect(cells).toEqual(["true", "false"]);
    });
});

// ---------------------------------------------------------------------------
// collectLinks
// ---------------------------------------------------------------------------

describe("collectLinks", () => {
    it("collects all links from a document", () => {
        const root = parse("[A](a.md) and [B](b.md#x)");
        const links = collectLinks(root);
        expect(links).toHaveLength(2);
        expect(links[0]!.url).toBe("a.md");
        expect(links[1]!.url).toBe("b.md#x");
    });

    it("returns empty for documents with no links", () => {
        const root = parse("Just plain text.");
        expect(collectLinks(root)).toHaveLength(0);
    });
});

// ---------------------------------------------------------------------------
// collectAnchors
// ---------------------------------------------------------------------------

describe("collectAnchors", () => {
    it("collects slugified heading anchors", () => {
        const root = parse("# First\n\n## Second Thing\n\n### Third");
        const anchors = collectAnchors(root);
        expect(anchors.has("first")).toBe(true);
        expect(anchors.has("second-thing")).toBe(true);
        expect(anchors.has("third")).toBe(true);
    });
});
