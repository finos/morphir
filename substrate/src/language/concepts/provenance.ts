/**
 * Provenance concept — corresponds to `specs/language/concepts/provenance.md`.
 *
 * Detects `### [Provenance](../concepts/provenance.md)` headings and
 * validates that at least one source link is present.
 */
import type { Content, Heading, Link, List } from "mdast";
import { detectConceptLink, nodeText, isList } from "../mdast-utils.js";

/** Returns true when the heading declares a Provenance section. */
export function isProvenanceHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "provenance";
}

/**
 * Check that a provenance section contains at least one source link.
 *
 * Returns true if at least one link is found in the body nodes.
 */
export function hasSourceLinks(body: readonly Content[]): boolean {
    for (const node of body) {
        if (isList(node)) {
            for (const item of (node as List).children) {
                if (containsLink(item)) return true;
            }
        }
    }
    return false;
}

function containsLink(node: unknown): boolean {
    if (typeof node !== "object" || node === null) return false;
    const obj = node as Record<string, unknown>;
    if (obj["type"] === "link" || obj["type"] === "linkReference") return true;
    const children = obj["children"];
    if (Array.isArray(children)) {
        for (const child of children) {
            if (containsLink(child)) return true;
        }
    }
    return false;
}
