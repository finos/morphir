// Tests for the MCK report record validator. Run with:
//   bun test tools/check-mck-report.test.ts
//
// check-mck-report.ts guards its CLI body behind `if (import.meta.main)`, so
// importing it here for `malformedRecordReason` does not attempt to read a
// report or call `process.exit`.
import { expect, test } from "bun:test";
import { malformedFormatVersionsReason, malformedRecordReason } from "./check-mck-report";

const valid = {
	caseId: "definitions-0001",
	irVersion: 4,
	profile: "json",
	role: "canonical",
	fenceIndex: 0,
	path: "current",
	result: "pass",
	durationMs: 1.5,
};

test("accepts a well-formed record", () => {
	expect(malformedRecordReason(valid, 0)).toBeNull();
});

test("accepts a record with no path, as a kit-error may have none", () => {
	const { path: _path, ...withoutPath } = valid;
	expect(malformedRecordReason({ ...withoutPath, result: "kit-error" }, 0)).toBeNull();
});

test("rejects a missing result instead of counting it as an unknown '?'", () => {
	const { result: _result, ...withoutResult } = valid;
	expect(malformedRecordReason(withoutResult, 0)).toMatch(/unrecognized result/);
});

test("rejects a result outside the schema's closed set", () => {
	expect(malformedRecordReason({ ...valid, result: "passed" }, 0)).toMatch(
		/unrecognized result/,
	);
});

test("rejects a non-string caseId", () => {
	expect(malformedRecordReason({ ...valid, caseId: 42 }, 0)).toMatch(/no string caseId/);
});

test("rejects an unrecognized profile, role, or path", () => {
	expect(malformedRecordReason({ ...valid, profile: "xml" }, 0)).toMatch(/unrecognized profile/);
	expect(malformedRecordReason({ ...valid, role: "narrator" }, 0)).toMatch(/unrecognized role/);
	expect(malformedRecordReason({ ...valid, path: "future" }, 0)).toMatch(/unrecognized path/);
});

test("rejects a non-number irVersion, fenceIndex, or durationMs", () => {
	expect(malformedRecordReason({ ...valid, irVersion: "4" }, 0)).toMatch(/no number irVersion/);
	expect(malformedRecordReason({ ...valid, fenceIndex: "0" }, 0)).toMatch(
		/no number fenceIndex/,
	);
	expect(malformedRecordReason({ ...valid, durationMs: "1.5" }, 0)).toMatch(
		/no number durationMs/,
	);
});

test("rejects a record that is not an object", () => {
	expect(malformedRecordReason(null, 0)).toMatch(/is not an object/);
	expect(malformedRecordReason("pass", 0)).toMatch(/is not an object/);
	expect(malformedRecordReason(["pass"], 0)).toMatch(/is not an object/);
});

/**
 * The report's top-level support table, `docs/spec/ir/format-version.md`,
 * Recognition and compatibility. The checker is a syntax gate: it takes the
 * table's canonical spelling, and the literal `unknown` a driver writes when the
 * adapter never answered capabilities.
 */
const report = {
	contractVersion: 1,
	binding: "morphir-typescript",
	language: "typescript",
	formatVersions: "[3.0.0,3.1.0),[4.0.0,4.1.0)",
	driverVersion: "0.0.1",
	kitVersion: "4a972bc3",
	startedAt: "2026-09-14T19:27:41.478Z",
	records: [valid],
};

test("accepts a canonical multi-interval support table", () => {
	expect(malformedFormatVersionsReason(report.formatVersions)).toBeNull();
});

test("names the field when a report carries no formatVersions", () => {
	const { formatVersions: _formatVersions, ...withoutTable } = report;
	expect(
		malformedFormatVersionsReason(
			(withoutTable as { formatVersions?: unknown }).formatVersions,
		),
	).toMatch(/formatVersions/);
});

test("rejects an inclusive upper bound that could be advanced", () => {
	expect(malformedFormatVersionsReason("[4.0.0,4.1.0]")).toMatch(
		/inclusive upper bound/,
	);
});

test("rejects an exclusive lower bound that could be advanced", () => {
	expect(malformedFormatVersionsReason("(4.0.0,4.1.0)")).toMatch(
		/exclusive lower bound/,
	);
});

test("accepts the two bracket shapes that cannot be advanced", () => {
	expect(malformedFormatVersionsReason("[4.0.0,4.0.4294967295]")).toBeNull();
	expect(malformedFormatVersionsReason("(4.0.4294967295,4.2.0)")).toBeNull();
});

test("accepts an absent bound without mistaking it for an advanceable one", () => {
	expect(malformedFormatVersionsReason("[4.0.0,)")).toBeNull();
	expect(malformedFormatVersionsReason("(,4.1.0)")).toBeNull();
});

test("does not misfire on a half-open interval beside a closed one", () => {
	// A single bracket scan that let a match run past `)` would read this as one
	// interval from 3.0.0 and blame the wrong bound.
	expect(malformedFormatVersionsReason("[3.0.0,3.1.0),[4.0.0,4.1.0]")).toMatch(
		/inclusive upper bound/,
	);
	expect(malformedFormatVersionsReason("[3.0.0,3.1.0),(4.0.0,4.1.0)")).toMatch(
		/exclusive lower bound/,
	);
	expect(
		malformedFormatVersionsReason("[3.0.0,3.1.0),[4.0.0,4.0.4294967295]"),
	).toBeNull();
});

test("rejects a table that is not in interval notation at all", () => {
	expect(malformedFormatVersionsReason("4.0.0")).toMatch(/canonical support table/);
	expect(malformedFormatVersionsReason("")).toMatch(/canonical support table/);
	expect(malformedFormatVersionsReason(4)).toMatch(/must be a string/);
});

test("rejects a release component above the unsigned 32-bit maximum", () => {
	// The corpus calls this table invalid ("component above range is invalid").
	expect(malformedFormatVersionsReason("[4.0.0,4.4294967296.0)")).toMatch(
		/out of range/,
	);
	expect(malformedFormatVersionsReason("[4294967296.0.0,)")).toMatch(/out of range/);
	// A longer patch is not the component maximum wearing a prefix.
	expect(malformedFormatVersionsReason("[4.0.0,4.0.14294967295]")).toMatch(
		/out of range/,
	);
	expect(malformedFormatVersionsReason("[4.0.0,4.4294967295.0)")).toBeNull();
});

test("accepts the literal unknown a capabilities-less run reports", () => {
	expect(malformedFormatVersionsReason("unknown")).toBeNull();
});
