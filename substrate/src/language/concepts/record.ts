/**
 * Record concept — corresponds to `specs/language/concepts/record.md`.
 *
 * Detects `### Name [Record](record.md)` headings and validates the
 * Fields section.
 */
import type { Content, Heading } from "mdast";
import { detectConceptLink, headingName, nodeText } from "../mdast-utils.js";

/** Returns true when the heading declares a Record. */
export function isRecordHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "record";
}

/** Extract the record name from a Record heading. */
export function recordName(heading: Heading): string {
    return headingName(heading);
}

/** Sections required in a Record declaration. */
export const REQUIRED_SECTIONS: readonly string[] = ["fields"];

/** Check whether all required sections are present. */
export function missingRecordSections(
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
