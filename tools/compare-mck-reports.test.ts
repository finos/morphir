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

const draft = (legacy: ReturnType<typeof report>) => ({
	contractVersion: "2.0.0-draft.1",
	suite: "ir",
	startedAt: legacy.startedAt,
	driver: { name: "morphir", version: "0.4.0", commit: null, dirty: false },
	kit: { version: legacy.kitVersion, source: "local", revision: null, snapshotDigest: null, corpusHash: null, modified: true },
	adapter: { command: ["adapter"], negotiation: { status: "succeeded", capabilities: {
		contractVersion: 1, binding: legacy.binding, language: legacy.language,
		formatVersions: legacy.formatVersions, versions: [4], profiles: ["json"], layouts: ["single"], paths: ["current"], nodes: ["Type"],
	} } },
	selection: { kind: "all" },
	execution: { strict: false, session: { status: "finished" } },
	records: legacy.records,
});

test("the approved draft projection preserves legacy result evidence", () => {
	const old = report([record()]);
	expect(compareReports(old, draft(old))).toEqual([]);
	expect(compareReports(old, draft(report([record({ result: "fail" })])))).toContain(
		'record 0 (types-0001 fence 0) result: "pass" vs "fail"',
	);
});

test("unknown report versions and unrecognized draft fields cannot disappear in projection", () => {
	const old = report([record()]);
	expect(compareReports(old, { ...draft(old), contractVersion: "2.0.0-draft.99" }).length).toBeGreaterThan(0);
	expect(compareReports(old, { ...draft(old), surprise: true }).length).toBeGreaterThan(0);
});
