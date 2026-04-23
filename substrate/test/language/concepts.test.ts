import { describe, it, expect } from "vitest";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, Heading, Content } from "mdast";
import { isOperationHeading, parseOperation } from "../../src/language/concepts/operation.js";
import { isTypeHeading, missingTypeSections } from "../../src/language/concepts/type.js";
import { isTypeClassHeading, missingTypeClassSections } from "../../src/language/concepts/type-class.js";
import { isChoiceHeading } from "../../src/language/concepts/choice.js";
import { isRecordHeading } from "../../src/language/concepts/record.js";
import { isDecisionTableHeading } from "../../src/language/concepts/decision-table.js";
import { isProvenanceHeading, hasSourceLinks } from "../../src/language/concepts/provenance.js";

function parse(md: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(md);
}

function findHeadingAndBody(root: Root, depth: number): { heading: Heading; body: Content[] } {
    for (let i = 0; i < root.children.length; i++) {
        const node = root.children[i]!;
        if (node.type === "heading" && (node as Heading).depth === depth) {
            const body: Content[] = [];
            for (let j = i + 1; j < root.children.length; j++) {
                const next = root.children[j]!;
                if (next.type === "heading" && (next as Heading).depth <= depth) break;
                body.push(next);
            }
            return { heading: node as Heading, body };
        }
    }
    throw new Error("heading not found");
}

// ---------------------------------------------------------------------------
// Operation concept
// ---------------------------------------------------------------------------

describe("isOperationHeading", () => {
    it("detects an operation heading with concept link", () => {
        const root = parse("### Not [Operation](../concepts/operation.md)");
        const { heading } = findHeadingAndBody(root, 3);
        expect(isOperationHeading(heading)).toBe(true);
    });

    it("rejects a non-operation heading", () => {
        const root = parse("### Overview");
        const { heading } = findHeadingAndBody(root, 3);
        expect(isOperationHeading(heading)).toBe(false);
    });
});

describe("parseOperation", () => {
    it("parses a required operation with test cases", () => {
        const md = `### Not [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md)_

Some description.

#### Test cases

| A | Not A |
|---|-------|
| \`true\` | \`false\` |
| \`false\` | \`true\` |
`;
        const root = parse(md);
        const { heading, body } = findHeadingAndBody(root, 3);
        const op = parseOperation(heading, body);
        expect(op.name).toBe("Not");
        expect(op.marker).toBe("required");
        expect(op.testCases).not.toBeNull();
        expect(op.testCases!.headers).toEqual(["A", "Not A"]);
        expect(op.testCases!.rows).toHaveLength(2);
        expect(op.testCases!.rows[0]!.cells).toEqual([true, false]);
    });

    it("parses a derived operation", () => {
        const md = `### Not Equal [Operation](../concepts/operation.md)

_[Derived](../concepts/operation.md)_

Defined in terms of [Equal](equality.md#equal).
`;
        const root = parse(md);
        const { heading, body } = findHeadingAndBody(root, 3);
        const op = parseOperation(heading, body);
        expect(op.marker).toBe("derived");
    });

    it("returns none marker when no marker present", () => {
        const md = `### Foo [Operation](../concepts/operation.md)\n\nNo marker here.`;
        const root = parse(md);
        const { heading, body } = findHeadingAndBody(root, 3);
        const op = parseOperation(heading, body);
        expect(op.marker).toBe("none");
    });
});

// ---------------------------------------------------------------------------
// Type concept
// ---------------------------------------------------------------------------

describe("isTypeHeading", () => {
    it("detects a type heading", () => {
        const root = parse("# Boolean [Type](../concepts/type.md)");
        const { heading } = findHeadingAndBody(root, 1);
        expect(isTypeHeading(heading)).toBe(true);
    });
});

describe("missingTypeSections", () => {
    it("reports missing sections when none are present", () => {
        const root = parse("# Boolean [Type](../concepts/type.md)\n\nJust text.");
        const { body } = findHeadingAndBody(root, 1);
        const missing = missingTypeSections(1, body);
        expect(missing.length).toBeGreaterThan(0);
    });

    it("reports no missing sections when all present", () => {
        const md = `# Boolean [Type](../concepts/type.md)

## Member Values

Values here.

## Type Class Instances

Instances here.
`;
        const root = parse(md);
        const { body } = findHeadingAndBody(root, 1);
        const missing = missingTypeSections(1, body);
        expect(missing).toHaveLength(0);
    });
});

// ---------------------------------------------------------------------------
// Type Class concept
// ---------------------------------------------------------------------------

describe("isTypeClassHeading", () => {
    it("detects a type-class heading", () => {
        const root = parse("# Equality [Type Class](../concepts/type-class.md)");
        const { heading } = findHeadingAndBody(root, 1);
        expect(isTypeClassHeading(heading)).toBe(true);
    });
});

// ---------------------------------------------------------------------------
// Other concepts
// ---------------------------------------------------------------------------

describe("isChoiceHeading", () => {
    it("detects a choice heading", () => {
        const root = parse("# Color [Choice](../concepts/choice.md)");
        const { heading } = findHeadingAndBody(root, 1);
        expect(isChoiceHeading(heading)).toBe(true);
    });
});

describe("isRecordHeading", () => {
    it("detects a record heading", () => {
        const root = parse("# Address [Record](../concepts/record.md)");
        const { heading } = findHeadingAndBody(root, 1);
        expect(isRecordHeading(heading)).toBe(true);
    });
});

describe("isDecisionTableHeading", () => {
    it("detects a decision-table heading", () => {
        const root = parse("# Rules [Decision Table](../concepts/decision-table.md)");
        const { heading } = findHeadingAndBody(root, 1);
        expect(isDecisionTableHeading(heading)).toBe(true);
    });
});

describe("isProvenanceHeading / hasSourceLinks", () => {
    it("detects provenance heading", () => {
        const root = parse("### [Provenance](../concepts/provenance.md)");
        const { heading } = findHeadingAndBody(root, 3);
        expect(isProvenanceHeading(heading)).toBe(true);
    });

    it("detects source links in body", () => {
        const md = `### [Provenance](../concepts/provenance.md)

- [Source](http://example.com)
`;
        const root = parse(md);
        const { body } = findHeadingAndBody(root, 3);
        expect(hasSourceLinks(body)).toBe(true);
    });

    it("detects reference-style source links in body", () => {
        const md = `### [Provenance](../concepts/provenance.md)

- [FR 2052a form][fr2052a-form]

[fr2052a-form]: http://example.com
`;
        const root = parse(md);
        const { body } = findHeadingAndBody(root, 3);
        expect(hasSourceLinks(body)).toBe(true);
    });

    it("reports missing source links", () => {
        const md = `### [Provenance](../concepts/provenance.md)

Just text, no links.
`;
        const root = parse(md);
        const { body } = findHeadingAndBody(root, 3);
        expect(hasSourceLinks(body)).toBe(false);
    });
});
