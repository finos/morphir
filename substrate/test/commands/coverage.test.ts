import { describe, it, expect } from "vitest";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { coverage, reportCoverage } from "../../src/commands/coverage.js";

const SPECS_EXPRS = resolve(
    fileURLToPath(new URL(".", import.meta.url)),
    "../../specs/language/expressions",
);

describe("coverage", () => {
    it(
        "returns a result with files and aggregate for a single spec file",
        async () => {
            const file = resolve(SPECS_EXPRS, "boolean.md");
            const result = await coverage(process.cwd(), [file]);
            expect(result.files).toHaveLength(1);
            expect(result.files[0]!.file).toBe(file);
            expect(result.aggregate).toBeDefined();
            expect(result.aggregate.totalNormativeAnchors).toBeGreaterThanOrEqual(0);
        },
        30_000,
    );

    it(
        "returns empty files array for a nonexistent path",
        async () => {
            const result = await coverage(process.cwd(), ["/nonexistent/path/xyz"]);
            expect(result.files).toHaveLength(0);
        },
        10_000,
    );

    it(
        "JSON output has the expected shape",
        async () => {
            const file = resolve(SPECS_EXPRS, "boolean.md");
            const result = await coverage(process.cwd(), [file]);
            const json = JSON.parse(reportCoverage(result, "json")) as unknown;
            expect(json).toHaveProperty("files");
            expect(json).toHaveProperty("aggregate");
            const obj = json as Record<string, unknown>;
            expect(Array.isArray(obj["files"])).toBe(true);
            const agg = obj["aggregate"] as Record<string, unknown>;
            expect(agg).toHaveProperty("totalNormativeAnchors");
            expect(agg).toHaveProperty("reachedAnchors");
            expect(agg).toHaveProperty("pct");
        },
        30_000,
    );

    it(
        "text output contains recognition and structural lines",
        async () => {
            const file = resolve(SPECS_EXPRS, "boolean.md");
            const result = await coverage(process.cwd(), [file]);
            const text = reportCoverage(result, "text");
            expect(text).toContain("recognition");
            expect(text).toContain("structural");
            expect(text).toContain("language coverage");
        },
        30_000,
    );

    it(
        "markdown output starts with a header",
        async () => {
            const file = resolve(SPECS_EXPRS, "boolean.md");
            const result = await coverage(process.cwd(), [file]);
            const md = reportCoverage(result, "markdown");
            expect(md).toMatch(/^# Coverage Report/);
        },
        30_000,
    );
});
