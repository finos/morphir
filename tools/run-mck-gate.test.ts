import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { runMckGate } from "./run-mck-gate";

// Only orchestration is under test here. Native report-check tests own verdicts.
function gate(runStatus: number, checkStatus: number, writesReport = true) {
	const dir = mkdtempSync(path.join(tmpdir(), "mck-gate-"));
	const report = path.join(dir, "report.json");
	const transcript = path.join(dir, "report.ndjson");
	const html = path.join(dir, "report.html");
	const log = path.join(dir, "calls.jsonl");
	const cli = path.join(dir, "cli.ts");
	writeFileSync(report, "stale");
	writeFileSync(transcript, "stale");
	writeFileSync(html, "stale");
	writeFileSync(cli, `
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(log)}, JSON.stringify(args) + "\\n");
if (args[0] === "run") {
  if (existsSync(${JSON.stringify(report)})) process.exit(90);
  if (existsSync(${JSON.stringify(transcript)})) process.exit(92);
  if (existsSync(${JSON.stringify(html)})) process.exit(93);
  ${writesReport ? `writeFileSync(${JSON.stringify(report)}, "fresh");` : ""}
  process.exit(${runStatus});
}
if (!existsSync(${JSON.stringify(report)})) process.exit(1);
if (readFileSync(${JSON.stringify(report)}, "utf8") !== "fresh") process.exit(91);
process.exit(${checkStatus});
`);
	try {
		const status = runMckGate(report, "baseline.json", "kit", "adapter", ["arg"], [process.execPath, cli]);
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
		["run", "--kit", "kit", "--report", result.report, "--html", result.report.replace(/\.json$/, ".html"), "--adapter", "bun", "--adapter-arg", "run", "--adapter-arg", "tools/record-mck-transcript.ts", "--adapter-arg", result.report.replace(/\.json$/, ".ndjson"), "--adapter-arg", "adapter", "--adapter-arg", "arg"],
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
