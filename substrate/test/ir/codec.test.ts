/**
 * Round-trip and smoke tests for the Morphir IR codec.
 *
 * Tests use the canonical fixture at `test/fixtures/morphir.json` which
 * mirrors the `sampleIRJSON` used in morphir-elm's own codec tests.
 */

import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it, expect } from "vitest";

import {
    tryDecodeVersionedDistribution,
    tryDecodeSubstrateDistribution,
    encodeVersionedDistribution,
    decodeTypeAttrs,
    decodeValueAttrs,
    encodeTypeAttrs,
    encodeValueAttrs,
    DecodeError,
} from "../../src/ir/codec.js";
import type { SubstrateDistribution } from "../../src/ir/attrs.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixturePath = resolve(__dirname, "../fixtures/morphir.json");

async function loadFixture(): Promise<unknown> {
    const raw = await readFile(fixturePath, "utf8");
    return JSON.parse(raw);
}

// ---------------------------------------------------------------------------
// Basic decode
// ---------------------------------------------------------------------------

describe("decodeVersionedDistribution (substrate attrs)", () => {
    it("decodes the fixture without errors", async () => {
        const json = await loadFixture();
        const result = tryDecodeVersionedDistribution(json, decodeTypeAttrs, decodeValueAttrs);
        expect(result.ok).toBe(true);
    });

    it("decoded distribution is a Library variant", async () => {
        const json = await loadFixture();
        const result = tryDecodeVersionedDistribution(json, decodeTypeAttrs, decodeValueAttrs);
        if (!result.ok) throw result.error;
        expect(result.value.kind).toBe("Library");
    });

    it("decoded package name is [['sample']]", async () => {
        const json = await loadFixture();
        const result = tryDecodeVersionedDistribution(json, decodeTypeAttrs, decodeValueAttrs);
        if (!result.ok) throw result.error;
        const dist = result.value;
        if (dist.kind !== "Library") throw new Error("Expected Library");
        expect(dist.packageName).toEqual([["sample"]]);
    });

    it("decoded modules include module:a and module:b", async () => {
        const json = await loadFixture();
        const result = tryDecodeVersionedDistribution(json, decodeTypeAttrs, decodeValueAttrs);
        if (!result.ok) throw result.error;
        const dist = result.value;
        if (dist.kind !== "Library") throw new Error("Expected Library");
        const moduleNames = dist.packageDef.modules.map(([path]) =>
            path.map((seg) => seg.join("_")).join("."),
        );
        expect(moduleNames).toContain("module_a");
        expect(moduleNames).toContain("module_b");
    });
});

// ---------------------------------------------------------------------------
// decodeSubstrateDistribution helper
// ---------------------------------------------------------------------------

describe("tryDecodeSubstrateDistribution", () => {
    it("is a convenience wrapper around decodeVersionedDistribution", async () => {
        const json = await loadFixture();
        const result = tryDecodeSubstrateDistribution(json);
        expect(result.ok).toBe(true);
    });

    it("returns DecodeError for invalid input", () => {
        const result = tryDecodeSubstrateDistribution({ formatVersion: 99, distribution: null });
        expect(result.ok).toBe(false);
        if (result.ok) throw new Error("Expected failure");
        expect(result.error).toBeInstanceOf(DecodeError);
    });

    it("returns DecodeError for non-object input", () => {
        const result = tryDecodeSubstrateDistribution(null);
        expect(result.ok).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// Round-trip: decode → encode → decode
// ---------------------------------------------------------------------------

describe("round-trip encode/decode (substrate attrs)", () => {
    it("re-encodes to structurally equivalent JSON", async () => {
        const json = await loadFixture();
        const r1 = tryDecodeVersionedDistribution(json, decodeTypeAttrs, decodeValueAttrs);
        if (!r1.ok) throw r1.error;

        const encoded = encodeVersionedDistribution(encodeTypeAttrs, encodeValueAttrs)(r1.value);
        const r2 = tryDecodeVersionedDistribution(encoded, decodeTypeAttrs, decodeValueAttrs);
        if (!r2.ok) throw r2.error;

        // Package name survives the trip
        if (r1.value.kind !== "Library" || r2.value.kind !== "Library") {
            throw new Error("Expected Library");
        }
        expect(r2.value.packageName).toEqual(r1.value.packageName);

        // Module count survives
        expect(r2.value.packageDef.modules.length).toBe(
            r1.value.packageDef.modules.length,
        );
    });
});

// ---------------------------------------------------------------------------
// Unparameterized (unit attrs) round-trip
// ---------------------------------------------------------------------------

describe("round-trip encode/decode (unit attrs {})", () => {
    it("decodes with trivial passthrough decoders", async () => {
        const json = await loadFixture();
        const passTA = (_: unknown) => ({} as Record<never, never>);
        const passVA = (_: unknown) => ({} as Record<never, never>);
        const encTA = (_: Record<never, never>) => ({} as unknown);
        const encVA = (_: Record<never, never>) => ({} as unknown);

        const r1 = tryDecodeVersionedDistribution(json, passTA, passVA);
        if (!r1.ok) throw r1.error;
        expect(r1.ok).toBe(true);

        const encoded = encodeVersionedDistribution(encTA, encVA)(r1.value);
        const r2 = tryDecodeVersionedDistribution(encoded, passTA, passVA);
        expect(r2.ok).toBe(true);
    });
});
