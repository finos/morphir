/**
 * Tests for the source-location index builder and lookup helpers.
 */

import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it, expect } from "vitest";

import { tryDecodeSubstrateDistribution } from "../../src/ir/codec.js";
import {
    buildSourceLocationIndex,
    lookupByNodePath,
    lookupByLocation,
} from "../../src/ir/source-location.js";
import type { SubstrateDistribution } from "../../src/ir/attrs.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixturePath = resolve(__dirname, "../fixtures/morphir.json");

async function loadDistribution(): Promise<SubstrateDistribution> {
    const raw = await readFile(fixturePath, "utf8");
    const json = JSON.parse(raw);
    const result = tryDecodeSubstrateDistribution(json);
    if (!result.ok) throw result.error;
    return result.value;
}

// ---------------------------------------------------------------------------
// buildSourceLocationIndex
// ---------------------------------------------------------------------------

describe("buildSourceLocationIndex", () => {
    it("returns an object with forward and reverse maps", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);
        expect(index).toHaveProperty("forward");
        expect(index).toHaveProperty("reverse");
        expect(index.forward).toBeInstanceOf(Map);
        expect(index.reverse).toBeInstanceOf(Map);
    });

    it("produces empty maps when no node has src attributes (fixture has no src)", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);
        // The fixture morphir.json has no substrate source-location attrs (empty TypeAttrs/ValueAttrs)
        expect(index.forward.size).toBe(0);
        expect(index.reverse.size).toBe(0);
    });
});

// ---------------------------------------------------------------------------
// lookupByNodePath
// ---------------------------------------------------------------------------

describe("lookupByNodePath", () => {
    it("returns undefined for a path not in the index", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);
        expect(lookupByNodePath(index, "nonexistent.path")).toBeUndefined();
    });

    it("returns the source location when the path exists (synthetic)", async () => {
        // Manually inject an entry to test the lookup
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);

        // Build a synthetic index with a known entry
        const src = { file: "foo.md", sectionId: "bar", text: "some text" };
        const syntheticForward = new Map(index.forward);
        syntheticForward.set("sample.module_a.foo", src);
        const syntheticIndex = { forward: syntheticForward, reverse: index.reverse };

        const found = lookupByNodePath(syntheticIndex, "sample.module_a.foo");
        expect(found).toEqual(src);
    });
});

// ---------------------------------------------------------------------------
// lookupByLocation
// ---------------------------------------------------------------------------

describe("lookupByLocation", () => {
    it("returns an empty set for a location with no nodes", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);
        const result = lookupByLocation(index, "foo.md", "nonexistent");
        expect(result.size).toBe(0);
    });

    it("returns the set of nodes anchored to a given location (synthetic)", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);

        const src = { file: "foo.md", sectionId: "sec1", text: "..." };
        const syntheticForward = new Map(index.forward);
        syntheticForward.set("sample.module_a.foo", src);
        syntheticForward.set("sample.module_a.bar", src);

        const nodeSet1 = new Set(["sample.module_a.foo", "sample.module_a.bar"]);
        const syntheticReverse = new Map(index.reverse);
        syntheticReverse.set("foo.md#sec1", nodeSet1);
        const syntheticIndex = { forward: syntheticForward, reverse: syntheticReverse };

        const found = lookupByLocation(syntheticIndex, "foo.md", "sec1");
        expect(found.size).toBe(2);
        expect(found.has("sample.module_a.foo")).toBe(true);
        expect(found.has("sample.module_a.bar")).toBe(true);
    });

    it("is the inverse of lookupByNodePath for synthetic data", async () => {
        const dist = await loadDistribution();
        const index = buildSourceLocationIndex(dist);

        const src = { file: "spec.md", sectionId: "s1", text: "foo type" };
        const nodePath = "sample.module_a.bar";

        const syntheticForward = new Map(index.forward);
        syntheticForward.set(nodePath, src);
        const nodeSet = new Set([nodePath]);
        const syntheticReverse = new Map(index.reverse);
        syntheticReverse.set("spec.md#s1", nodeSet);
        const syntheticIndex = { forward: syntheticForward, reverse: syntheticReverse };

        const foundSrc = lookupByNodePath(syntheticIndex, nodePath);
        expect(foundSrc).toEqual(src);

        const foundNodes = lookupByLocation(syntheticIndex, src.file, src.sectionId);
        expect(foundNodes.has(nodePath)).toBe(true);
    });
});
