/**
 * Resolve a semver range against the set of tags on a remote
 * repository. Tags may be prefixed with `v` or not; both are accepted.
 */
import { maxSatisfying, valid as validVersion } from "semver";

import type { RemoteTag } from "./git.js";

/**
 * Given a set of remote tags and a semver range, return the best tag
 * satisfying the range (highest satisfying version) or null if none.
 */
export function pickBestTag(
    tags: readonly RemoteTag[],
    range: string,
): RemoteTag | null {
    const byVersion = new Map<string, RemoteTag>();
    for (const t of tags) {
        const normalised = normaliseTag(t.tag);
        if (normalised === null) continue;
        // Prefer the tag with leading `v` when both exist.
        const existing = byVersion.get(normalised);
        if (existing === undefined || t.tag.startsWith("v")) {
            byVersion.set(normalised, t);
        }
    }

    const versions = Array.from(byVersion.keys());
    const best = maxSatisfying(versions, range);
    if (best === null) return null;
    return byVersion.get(best) ?? null;
}

/**
 * Convert a tag string into a canonical semver string (stripping an
 * optional leading `v`), or null if the tag is not a valid version.
 */
export function normaliseTag(tag: string): string | null {
    const stripped = tag.startsWith("v") ? tag.slice(1) : tag;
    return validVersion(stripped);
}
