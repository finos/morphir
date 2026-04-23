/**
 * Type concept — corresponds to `specs/language/concepts/type.md`.
 *
 * Detects `# Name [Type](../concepts/type.md)` headings and validates
 * that the module contains the required Member Values and Type Class
 * Instances sections.
 */
import type { Content, Heading } from "mdast";
import { detectConceptLink, headingName, isHeading, nodeText } from "../mdast-utils.js";

/** Returns true when the heading declares a Type. */
export function isTypeHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "type";
}

/** Extract the type name from a Type heading. */
export function typeName(heading: Heading): string {
    return headingName(heading);
}

/** Sections required in a Type module. */
export const REQUIRED_SECTIONS: readonly string[] = [
    "member values",
    "type class instances",
];

/**
 * Check whether all required sections are present as subheadings
 * under the type heading.
 *
 * Returns the names of any missing sections.
 */
export function missingTypeSections(
    typeDepth: number,
    body: readonly Content[],
): readonly string[] {
    const found = new Set<string>();
    for (const node of body) {
        if (node.type === "heading") {
            const h = node as Heading;
            if (h.depth <= typeDepth) break; // exited this type's scope
            found.add(nodeText(h).toLowerCase());
        }
    }
    return REQUIRED_SECTIONS.filter((s) => !found.has(s));
}
