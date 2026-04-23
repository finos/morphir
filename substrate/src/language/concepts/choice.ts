/**
 * Choice concept — corresponds to `specs/language/concepts/choice.md`.
 *
 * Detects `### Name [Choice](choice.md)` headings and validates the
 * Variants section.
 */
import type { Content, Heading } from "mdast";
import { detectConceptLink, headingName, nodeText } from "../mdast-utils.js";

/** Returns true when the heading declares a Choice. */
export function isChoiceHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "choice";
}

/** Extract the choice name from a Choice heading. */
export function choiceName(heading: Heading): string {
    return headingName(heading);
}

/** Sections required in a Choice declaration. */
export const REQUIRED_SECTIONS: readonly string[] = ["variants"];

/** Check whether all required sections are present. */
export function missingChoiceSections(
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
