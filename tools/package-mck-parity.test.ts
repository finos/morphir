import { expect, test } from "bun:test";
import { assertPackageParity, nativePackageInvocations } from "./package-mck-parity.ts";

function report() {
	return {
		suite: "package", contractVersion: "0.1.0-draft.1", driverVersion: "old", startedAt: "old-time",
		kit: { formatVersion: "0.1.0-draft.1", contentHash: "sha256-fixed" },
		testee: { implementation: "fixture", operations: ["normalize"] },
		records: Array.from({ length: 80 }, (_, i) => ({ caseId: `case-${i}`, operation: "normalize", result: "pass" })),
	};
}

test("migration parity ignores only runner identity and start time", () => {
	const old = report();
	expect(() => assertPackageParity(old, { ...old, driverVersion: "new", startedAt: "new-time" })).not.toThrow();
});

test("migration parity preserves inventory, ordering, capabilities, hash and messages", () => {
	for (const mutate of [
		(r: ReturnType<typeof report>) => { r.records.reverse(); },
		(r: ReturnType<typeof report>) => { r.records.pop(); },
		(r: ReturnType<typeof report>) => { r.testee.operations.push("validate"); },
		(r: ReturnType<typeof report>) => { r.kit.contentHash = "different"; },
		(r: ReturnType<typeof report>) => { Object.assign(r.records[0]!, { message: "changed" }); },
	]) {
		const changed = report();
		mutate(changed);
		expect(() => assertPackageParity(report(), changed)).toThrow();
	}
});

test("matching empty or incomplete reports cannot establish package parity", () => {
	for (const records of [[], report().records.slice(1)]) {
		const partial = { ...report(), records };
		expect(() => assertPackageParity(partial, partial)).toThrow();
	}
});

test("matching failures and required skips cannot establish migration readiness", () => {
	for (const result of ["fail", "kit-error", "skipped"]) {
		const r = report();
		r.records[0]!.result = result;
		expect(() => assertPackageParity(r, r)).toThrow();
	}
});

test("draft.2 requires exactly 78 matching passing records", () => {
	const r = report();
	r.contractVersion = r.kit.formatVersion = "0.1.0-draft.2";
	r.records = r.records.slice(0, 78);
	expect(() => assertPackageParity(r, r)).not.toThrow();
});

test("native parity selects both contracts on two external adapters with separate reports", () => {
	for (const platform of ["linux", "win32"]) {
		const runs = nativePackageInvocations("/a repository", platform);
		expect(runs).toHaveLength(4);
		expect(new Set(runs.map((run) => run.report)).size).toBe(4);
		for (const run of runs) {
			expect(run.command.slice(0, 8)).toEqual(["cargo", "run", "--locked", "--package", "morphir", "--", "mck", "package"]);
			expect(run.command).toContain("--adapter");
			const contract = run.command[run.command.indexOf("--contract") + 1];
			expect(run.command.filter((arg) => arg === contract)).toHaveLength(2);
			expect(run.report).not.toBe(run.baseline);
			if (run.baseline.endsWith("rust.json")) {
				expect(run.command[run.command.indexOf("--adapter") + 1]).toEndWith(platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust");
			} else expect(run.command[run.command.indexOf("--adapter") + 1]).toBe("bun");
		}
	}
});
