import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { runMckGate, runMckParity } from "./run-mck-gate";

// Only orchestration is under test here. Native report-check tests own verdicts.
function gate(runStatus: number, checkStatus: number, writesReport = true) {
	const dir = mkdtempSync(path.join(tmpdir(), "mck-gate-"));
	const report = path.join(dir, "report.json");
	const log = path.join(dir, "calls.jsonl");
	const cli = path.join(dir, "cli.ts");
	writeFileSync(report, "stale");
	writeFileSync(cli, `
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(log)}, JSON.stringify(args) + "\\n");
if (args[0] === "run") {
  if (existsSync(${JSON.stringify(report)})) process.exit(90);
  ${writesReport ? `writeFileSync(${JSON.stringify(report)}, "fresh");` : ""}
  process.exit(${runStatus});
}
if (!existsSync(${JSON.stringify(report)})) process.exit(1);
if (readFileSync(${JSON.stringify(report)}, "utf8") !== "fresh") process.exit(91);
process.exit(${checkStatus});
`);
	try {
		const status = runMckGate(report, "baseline.json", "kit", ["--adapter", "adapter"], [process.execPath, cli]);
		const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
		return { status, calls, report };
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test("native checker can accept a runner's allowed failures", () => {
	const result = gate(1, 0);
	expect(result.status).toBe(0);
	expect(result.calls).toEqual([
		["run", "--kit", "kit", "--report", result.report, "--adapter", "adapter"],
		["report", "check", result.report, "baseline.json", "--kit", "kit"],
	]);
});

test("native checker rejects unexpected failures and stale baselines", () => {
	expect(gate(1, 1).status).toBe(1);
	expect(gate(0, 1).status).toBe(1);
});

test("a run that writes no report cannot reuse stale evidence", () => {
	expect(gate(1, 0, false).status).toBe(1);
});

for (const status of [2, 101, 130]) {
	test(`runner status ${status} is propagated without checking`, () => {
		const result = gate(status, 0);
		expect(result.status).toBe(status);
		expect(result.calls).toHaveLength(1);
	});
}

// Only orchestration is under test here. The native report comparer owns every verdict.
function parity(runStatus: number, compareStatus: number, writesReport = true) {
	const dir = mkdtempSync(path.join(tmpdir(), "mck-parity-"));
	const legacyReport = path.join(dir, "legacy.json");
	const gherkinReport = path.join(dir, "gherkin.json");
	const log = path.join(dir, "calls.jsonl");
	const cli = path.join(dir, "cli.ts");
	writeFileSync(legacyReport, "legacy");
	writeFileSync(gherkinReport, "stale");
	writeFileSync(cli, `
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(log)}, JSON.stringify(args) + "\\n");
if (args[0] === "run") {
  if (existsSync(${JSON.stringify(gherkinReport)})) process.exit(90);
  ${writesReport ? `writeFileSync(${JSON.stringify(gherkinReport)}, "fresh");` : ""}
  process.exit(${runStatus});
}
if (!existsSync(${JSON.stringify(gherkinReport)})) process.exit(1);
if (readFileSync(${JSON.stringify(gherkinReport)}, "utf8") !== "fresh") process.exit(91);
process.exit(${compareStatus});
`);
	try {
		const status = runMckParity(
			legacyReport,
			gherkinReport,
			"kit",
			["--adapter", "adapter"],
			[process.execPath, cli],
		);
		const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
		// The legacy report is only ever read, never rewritten by the parity gate;
		// read it back before the temp dir goes away.
		const legacyReportContent = readFileSync(legacyReport, "utf8");
		return { status, calls, legacyReport, gherkinReport, legacyReportContent };
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test("parity reuses the legacy report and compares it with a fresh gherkin run", () => {
	const result = parity(1, 0);
	expect(result.status).toBe(0);
	expect(result.calls).toEqual([
		["run", "--engine", "gherkin", "--kit", "kit", "--report", result.gherkinReport, "--adapter", "adapter"],
		["report", "compare", result.legacyReport, result.gherkinReport],
	]);
	expect(result.legacyReportContent).toBe("legacy");
});

test("parity rejects a report mismatch", () => {
	expect(parity(0, 1).status).toBe(1);
	expect(parity(1, 1).status).toBe(1);
});

test("a gherkin run that writes no report cannot reuse stale evidence", () => {
	expect(parity(1, 0, false).status).toBe(1);
});

for (const status of [2, 101, 130]) {
	test(`gherkin runner status ${status} is propagated without comparing`, () => {
		const result = parity(status, 0);
		expect(result.status).toBe(status);
		expect(result.calls).toHaveLength(1);
	});
}
