import { describe, it, expect } from "vitest";

import { normaliseTag, pickBestTag } from "../../src/package/resolve.js";
import type { RemoteTag } from "../../src/package/git.js";

const tags = (pairs: ReadonlyArray<readonly [string, string]>): RemoteTag[] =>
    pairs.map(([tag, commit]) => ({ tag, commit }));

describe("normaliseTag", () => {
    it("accepts both v-prefixed and bare tags", () => {
        expect(normaliseTag("v1.2.3")).toBe("1.2.3");
        expect(normaliseTag("1.2.3")).toBe("1.2.3");
    });

    it("returns null for non-version tags", () => {
        expect(normaliseTag("release")).toBe(null);
        expect(normaliseTag("v1")).toBe(null);
    });
});

describe("pickBestTag", () => {
    it("returns the highest tag satisfying a caret range", () => {
        const picked = pickBestTag(
            tags([
                ["v0.1.0", "aaa"],
                ["v0.1.3", "bbb"],
                ["v0.2.0", "ccc"],
            ]),
            "^0.1.0",
        );
        expect(picked?.tag).toBe("v0.1.3");
    });

    it("returns null when no tag satisfies the range", () => {
        const picked = pickBestTag(
            tags([["v0.1.0", "aaa"]]),
            "^1.0.0",
        );
        expect(picked).toBe(null);
    });

    it("ignores non-version refs", () => {
        const picked = pickBestTag(
            tags([
                ["latest", "zzz"],
                ["v1.0.0", "aaa"],
            ]),
            "^1.0.0",
        );
        expect(picked?.tag).toBe("v1.0.0");
    });

    it("prefers the v-prefixed duplicate when both forms exist", () => {
        const picked = pickBestTag(
            tags([
                ["1.0.0", "aaa"],
                ["v1.0.0", "bbb"],
            ]),
            "^1.0.0",
        );
        expect(picked?.tag).toBe("v1.0.0");
    });
});
