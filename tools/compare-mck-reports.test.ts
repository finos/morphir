import { expect, test } from "bun:test";
import { compareReports, PERMITTED } from "./compare-mck-reports.ts";

const report = (records: unknown[], extra: Record<string, unknown> = {}) => ({
	contractVersion: 1,
	binding: "morphir-rust",
	language: "rust",
	formatVersions: "[4.0.0,4.1.0)",
	startedAt: "2026-09-19T00:00:00.000Z",
	durationMs: 12,
	driverVersion: "0.4.0",
	kitVersion: "abc",
	records,
	...extra,
});

const record = (extra: Record<string, unknown> = {}) => ({
	caseId: "types-0001",
	irVersion: 4,
	profile: "json",
	role: "canonical",
	fenceIndex: 0,
	path: "current",
	result: "pass",
	durationMs: 3,
	...extra,
});

test("reports agree when only timing and the driver's own identity differ", () => {
	const old = report([record()]);
	const fresh = report([record({ durationMs: 99 })], {
		startedAt: "2027-01-01T00:00:00.000Z",
		durationMs: 7,
		driverVersion: "morphir 0.5.0",
	});
	expect(compareReports(old, fresh)).toEqual([]);
	expect(PERMITTED).toEqual(["startedAt", "durationMs", "driverVersion"]);
});

test("a differing verdict is named with both sides", () => {
	const differences = compareReports(
		report([record()]),
		report([record({ result: "fail", message: "line 1 differs" })]),
	);
	expect(differences).toEqual([
		`record 0 (types-0001 fence 0) result: "pass" vs "fail"`,
		`record 0 (types-0001 fence 0) message: undefined vs "line 1 differs"`,
	]);
});

test("a missing or extra record is a difference, not a silent truncation", () => {
	const two = report([record(), record({ fenceIndex: 1 })]);
	const one = report([record()]);
	expect(compareReports(two, one)).toEqual(["record count: 2 vs 1"]);
	expect(compareReports(one, two)).toEqual(["record count: 1 vs 2"]);
});

test("a differing header member is a difference", () => {
	expect(compareReports(report([]), report([], { binding: "other" })))
		.toEqual([`binding: "morphir-rust" vs "other"`]);
	expect(compareReports(report([]), report([], { kitVersion: "def" })))
		.toEqual([`kitVersion: "abc" vs "def"`]);
});

test("records are compared in order, so a reordered report is not parity", () => {
	const a = report([record(), record({ caseId: "types-0002" })]);
	const b = report([record({ caseId: "types-0002" }), record()]);
	expect(compareReports(a, b)).toHaveLength(2);
});
