/**
 * Decision Table concept — corresponds to `specs/language/concepts/decision-table.md`.
 *
 * Detects `### Name [Decision Table](decision-table.md)` headings and
 * validates the Inputs, Outputs, and Rules sections.
 */
import type { Content, Heading } from "mdast";
import { detectConceptLink, headingName, nodeText } from "../mdast-utils.js";

/** Returns true when the heading declares a Decision Table. */
export function isDecisionTableHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "decision-table";
}

/** Extract the name from a Decision Table heading. */
export function decisionTableName(heading: Heading): string {
    return headingName(heading);
}

/** Sections required in a Decision Table declaration. */
export const REQUIRED_SECTIONS: readonly string[] = [
    "inputs",
    "outputs",
    "rules",
];

/** Check whether all required sections are present. */
export function missingDecisionTableSections(
    depth: number,
    body: readonly Content[],
): readonly string[] {
    const found = new Set<string>();
    for (const node of body) {
        if (node.type === "heading") {
            const h = node as Heading;
            if (h.depth <= depth) break;
            found.add(nodeText(h).toLowerCase());
        }
    }
    return REQUIRED_SECTIONS.filter((s) => !found.has(s));
}
