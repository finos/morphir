import { describe, it, expect } from "vitest";
import { resolve } from "node:path";
import { verify } from "../src/pipeline.js";
import type { ProgressEvent } from "../src/types.js";

const SPECS_DIR = resolve(import.meta.dirname, "../specs");

describe("verify pipeline", () => {
    it("runs all stages on a valid spec file", async () => {
        const events: ProgressEvent[] = [];
        const result = await verify(
            resolve(SPECS_DIR, "language/expressions/boolean.md"),
            (e) => events.push(e),
        );
        // Should have all 6 stages
        expect(result.stages).toHaveLength(6);
        expect(result.stages.map((s) => s.stage)).toEqual([
            "parse",
            "include",
            "lint",
            "references",
            "typecheck",
            "test",
        ]);
        // Should have received progress events
        expect(events.length).toBeGreaterThan(0);
        expect(events.some((e) => e.kind === "stage-start")).toBe(true);
        expect(events.some((e) => e.kind === "stage-end")).toBe(true);
    });

    it("stops early on parse failure", async () => {
        const result = await verify(resolve(SPECS_DIR, "nonexistent.md"));
        expect(result.stages).toHaveLength(1);
        expect(result.stages[0]!.stage).toBe("parse");
        expect(result.stages[0]!.diagnostics.some((d) => d.severity === "error")).toBe(true);
    });

    it("reports total duration", async () => {
        const result = await verify(
            resolve(SPECS_DIR, "language/expressions/boolean.md"),
        );
        expect(result.totalDurationMs).toBeGreaterThan(0);
    });
});
