/**
 * Stage 3: Lint — structural validation of the document.
 *
 * Checks:
 * - Heading hierarchy: levels increment by at most 1.
 * - Required sections for each concept kind.
 * - Operation headings have test-case tables.
 * - Operations have Required/Derived markers.
 */
import type { Root, Content, Heading } from "mdast";
import type { Diagnostic } from "../types.js";
import {
    detectConceptLink,
    headingName,
    nodeText,
} from "../language/mdast-utils.js";
import {
    isOperationHeading,
    parseOperation,
} from "../language/concepts/operation.js";
import { isTypeHeading, missingTypeSections } from "../language/concepts/type.js";
import { isTypeClassHeading, missingTypeClassSections } from "../language/concepts/type-class.js";
import { isRecordHeading, missingRecordSections } from "../language/concepts/record.js";
import { isChoiceHeading, missingChoiceSections } from "../language/concepts/choice.js";
import {
    isDecisionTableHeading,
    missingDecisionTableSections,
} from "../language/concepts/decision-table.js";
import { isProvenanceHeading, hasSourceLinks } from "../language/concepts/provenance.js";

/**
 * Lint the document structure and return diagnostics.
 */
export function lintDocument(
    root: Root,
    filePath: string,
): readonly Diagnostic[] {
    const diagnostics: Diagnostic[] = [];

    diagnostics.push(...checkHeadingHierarchy(root, filePath));
    diagnostics.push(...checkConceptSections(root, filePath));

    return diagnostics;
}

// ---------------------------------------------------------------------------
// Heading hierarchy (MD001 equivalent)
// ---------------------------------------------------------------------------

function checkHeadingHierarchy(root: Root, filePath: string): readonly Diagnostic[] {
    const diags: Diagnostic[] = [];
    let prevDepth = 0;

    for (const node of root.children) {
        if (node.type !== "heading") continue;
        const h = node as Heading;
        if (prevDepth > 0 && h.depth > prevDepth + 1) {
            diags.push({
                stage: "lint",
                severity: "warning",
                file: filePath,
                line: h.position?.start.line,
                message: `Heading level jumps from h${prevDepth} to h${h.depth} (expected at most h${prevDepth + 1})`,
                ruleId: "heading-increment",
            });
        }
        prevDepth = h.depth;
    }

    return diags;
}

// ---------------------------------------------------------------------------
// Concept-specific section validation
// ---------------------------------------------------------------------------

function checkConceptSections(root: Root, filePath: string): readonly Diagnostic[] {
    const diags: Diagnostic[] = [];
    const children = root.children;

    for (let i = 0; i < children.length; i++) {
        const node = children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;

        // Collect body nodes until next sibling heading
        const body = collectBody(children, i, heading.depth);

        // Type modules
        if (isTypeHeading(heading)) {
            const missing = missingTypeSections(heading.depth, body);
            for (const section of missing) {
                diags.push({
                    stage: "lint",
                    severity: "error",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Type "${headingName(heading)}" is missing required section: ${section}`,
                    ruleId: "type-missing-section",
                });
            }
        }

        // Type Class modules
        if (isTypeClassHeading(heading)) {
            const missing = missingTypeClassSections(heading.depth, body);
            for (const section of missing) {
                diags.push({
                    stage: "lint",
                    severity: "error",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Type class "${headingName(heading)}" is missing required section: ${section}`,
                    ruleId: "type-class-missing-section",
                });
            }
        }

        // Records
        if (isRecordHeading(heading)) {
            const missing = missingRecordSections(heading.depth, body);
            for (const section of missing) {
                diags.push({
                    stage: "lint",
                    severity: "error",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Record "${headingName(heading)}" is missing required section: ${section}`,
                    ruleId: "record-missing-section",
                });
            }
        }

        // Choices
        if (isChoiceHeading(heading)) {
            const missing = missingChoiceSections(heading.depth, body);
            for (const section of missing) {
                diags.push({
                    stage: "lint",
                    severity: "error",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Choice "${headingName(heading)}" is missing required section: ${section}`,
                    ruleId: "choice-missing-section",
                });
            }
        }

        // Decision Tables
        if (isDecisionTableHeading(heading)) {
            const missing = missingDecisionTableSections(heading.depth, body);
            for (const section of missing) {
                diags.push({
                    stage: "lint",
                    severity: "error",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Decision table "${headingName(heading)}" is missing required section: ${section}`,
                    ruleId: "decision-table-missing-section",
                });
            }
        }

        // Operations: must have marker and test cases
        if (isOperationHeading(heading)) {
            const op = parseOperation(heading, body);
            if (op.marker === "none") {
                diags.push({
                    stage: "lint",
                    severity: "warning",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Operation "${op.name}" has no Required/Derived marker`,
                    ruleId: "operation-missing-marker",
                });
            }
            if (op.testCases === null) {
                diags.push({
                    stage: "lint",
                    severity: "warning",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: `Operation "${op.name}" has no test-case table`,
                    ruleId: "operation-missing-tests",
                });
            }
        }

        // Provenance: must have source links
        if (isProvenanceHeading(heading)) {
            if (!hasSourceLinks(body)) {
                diags.push({
                    stage: "lint",
                    severity: "warning",
                    file: filePath,
                    line: heading.position?.start.line,
                    message: "Provenance section has no source links",
                    ruleId: "provenance-missing-sources",
                });
            }
        }
    }

    return diags;
}

/**
 * Collect content nodes following a heading until the next heading at
 * the same or higher level.
 */
function collectBody(
    children: readonly Content[],
    headingIndex: number,
    headingDepth: number,
): readonly Content[] {
    const body: Content[] = [];
    for (let j = headingIndex + 1; j < children.length; j++) {
        const node = children[j]!;
        if (node.type === "heading" && (node as Heading).depth <= headingDepth) {
            break;
        }
        body.push(node);
    }
    return body;
}
