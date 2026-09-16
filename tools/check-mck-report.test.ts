// Tests for the MCK report record validator. Run with:
//   bun test tools/check-mck-report.test.ts
//
// check-mck-report.ts guards its CLI body behind `if (import.meta.main)`, so
// importing it here for `malformedRecordReason` does not attempt to read a
// report or call `process.exit`.
import { expect, test } from "bun:test";
import { malformedRecordReason } from "./check-mck-report";

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
