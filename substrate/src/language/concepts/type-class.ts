/**
 * Type Class concept — corresponds to `specs/language/concepts/type-class.md`.
 *
 * Detects `# Name [Type Class](../concepts/type-class.md)` headings and
 * validates the Operations section.
 */
import type { Content, Heading } from "mdast";
import { detectConceptLink, headingName, nodeText } from "../mdast-utils.js";

/** Returns true when the heading declares a Type Class. */
export function isTypeClassHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "type-class";
}

/** Extract the type class name from a Type Class heading. */
export function typeClassName(heading: Heading): string {
    return headingName(heading);
}

/** Sections required in a Type Class module. */
export const REQUIRED_SECTIONS: readonly string[] = ["operations"];

/**
 * Check whether all required sections are present.
 * Returns the names of any missing sections.
 */
export function missingTypeClassSections(
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
