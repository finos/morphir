// Tests for the WASM host report controls check. Run with:
//   bun test tools/check-wasm-host-report.test.ts
//
// check-wasm-host-report.ts guards its CLI body behind `if (import.meta.main)`,
// so importing it here does not run the check.
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
	checkControls,
	checkSummary,
	type Controls,
	EXAMPLE,
	loadReportInput,
	naturalOutcome,
	outcomeConsistent,
	REPORT_SCHEMA,
	type ReportInput,
	schemaProblems,
	summarize,
} from "./check-wasm-host-report";

const root = path.resolve(import.meta.dir, "..");
const input = loadReportInput(root);
const jsonschema = process.env.MORPHIR_JSONSCHEMA ?? "jsonschema";
const hasCli = spawnSync(jsonschema, ["--version"], { windowsHide: true }).status === 0;

/** The failures of the committed controls after `change` edits a copy of them. */
function failuresAfter(change: (controls: Controls, input: ReportInput) => void): string[] {
	const copy: ReportInput = { ...input, controls: structuredClone(input.controls) };
	change(copy.controls, copy);
	return checkControls(copy);
}

test("the committed controls pass", () => {
	expect(checkControls(input)).toEqual([]);
});

test("deleting any one control fails the check on coverage", () => {
	for (const control of input.controls.controls) {
		const failures = failuresAfter((controls) => {
			controls.controls = controls.controls.filter((entry) => entry.id !== control.id);
		});
		expect(failures).toContain(`spec/mep/mck/wasm-host-report.controls.json: no control covers ${control.covers}`);
	}
});

test("a control with another verdict than the rule gives fails", () => {
	const failures = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "deadline-not-enforced");
		if (control) control.expect = { qualified: true, reasons: [] };
	});
	expect(failures.some((failure) => failure.includes("control deadline-not-enforced: expects"))).toBe(true);
});

test("reasons out of the fixed order fail", () => {
	const failures = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "reasons-in-order");
		if (control && "reasons" in control.expect) control.expect.reasons.reverse();
	});
	expect(failures.some((failure) => failure.includes("control reasons-in-order: expects"))).toBe(true);
});

test("a control that names a case the corpus lacks fails", () => {
	const failures = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "qualified");
		if (control) control.change = { outcomes: { "bounds/no-such-case": "failed" } };
	});
	expect(failures).toContain("spec/mep/mck/wasm-host-report.controls.json: control qualified: the corpus has no case bounds/no-such-case");
});

test("two controls cannot cover one element", () => {
	const failures = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "budget-not-enforced");
		if (control) control.covers = "qualified";
	});
	expect(failures.some((failure) => failure.includes("already covers"))).toBe(true);
});

test("the rule's orders must follow the contract and the report schema", () => {
	expect(failuresAfter((controls) => controls.rule.profileOrder.reverse()).some((failure) => failure.includes("rule.profileOrder"))).toBe(true);
	expect(failuresAfter((controls) => controls.rule.reasons.reverse()).some((failure) => failure.includes("rule.reasons"))).toBe(true);
});

test("the document must state every code", () => {
	const failures = failuresAfter((_, copy) => {
		copy.document = copy.document.replaceAll("`verdict_mismatch`", "");
	});
	expect(failures).toContain("spec/mep/mck/wasm-host-report.md: the document does not state the refusal code, `verdict_mismatch`");
});

test("the outcome that follows from the declarations", () => {
	const enforced = { memoryCeiling: "enforced", instructionBudget: "enforced", callDeadline: "enforced" } as const;
	const budget = { caseId: "bounds/small-budget", appliesTo: "extism-kernel-v1", bounds: ["instructionBudget"] };
	const bytes = { caseId: "bounds/spin-bytes", appliesTo: "morphir-bytes-v1", bounds: ["callDeadline"] };
	expect(naturalOutcome(budget, ["extism-kernel-v1"], enforced)).toBe("passed");
	expect(naturalOutcome(budget, ["extism-kernel-v1"], { ...enforced, instructionBudget: "not-enforced" })).toBe("not_enforced");
	expect(naturalOutcome(budget, ["extism-kernel-v1"], { ...enforced, instructionBudget: "undeclared" })).toBe("error");
	// The profile comes first: an undeclared profile is not applicable whatever its bounds say.
	expect(naturalOutcome(bytes, ["extism-kernel-v1"], { ...enforced, callDeadline: "inconsistent" })).toBe("not_applicable");
});

test("which recorded outcomes a declaration allows", () => {
	expect(outcomeConsistent("passed", "failed")).toBe(true);
	expect(outcomeConsistent("passed", "refused")).toBe(true);
	expect(outcomeConsistent("passed", "not_enforced")).toBe(false);
	expect(outcomeConsistent("passed", "not_applicable")).toBe(false);
	expect(outcomeConsistent("not_enforced", "passed")).toBe(false);
	expect(outcomeConsistent("not_enforced", "failed")).toBe(false);
	expect(outcomeConsistent("not_enforced", "refused")).toBe(true);
	expect(outcomeConsistent("error", "passed")).toBe(false);
	expect(outcomeConsistent("not_applicable", "passed")).toBe(false);
	expect(outcomeConsistent("not_applicable", "not_applicable")).toBe(true);
});

test("a repeated or reordered case is refused", () => {
	expect(checkSummary(input, summarize(input, { duplicateCases: ["bounds/spin-extism"] }))).toEqual({ rejected: ["case_inventory"] });
	expect(checkSummary(input, summarize(input, { swapCases: ["bounds/spin-extism", "bounds/small-budget"] }))).toEqual({
		rejected: ["case_inventory"],
	});
});

test("every refusal that applies is given, in the rule's order", () => {
	const result = checkSummary(
		input,
		summarize(input, { host: { engine: null }, removeCases: ["bounds/spin-extism"], storedVerdict: { qualified: false, reasons: [] } }),
	);
	expect(result).toEqual({ rejected: ["identity_missing", "case_inventory", "verdict_mismatch"] });
});

test("a host that enforces nothing optional and fails nothing is qualified with its budget case not enforced", () => {
	const summary = summarize(input, { bounds: { instructionBudget: "not-enforced" } });
	expect(summary.cases.find((entry) => entry.caseId === "bounds/small-budget")?.outcome).toBe("not_enforced");
	expect(summary.totals).toMatchObject({ cases: 59, passed: 48, notApplicable: 10, notEnforced: 1 });
	expect(checkSummary(input, summary)).toEqual({ qualified: true, reasons: [] });
});

test.skipIf(!hasCli)("the schemas are valid and the controls and the example validate", () => {
	expect(schemaProblems(root)).toEqual([]);
});

test.skipIf(!hasCli)("the report schema refuses a reason with the wrong member and an unknown outcome", () => {
	const scratch = mkdtempSync(path.join(tmpdir(), "wasm-host-report-"));
	try {
		const refuses = (edit: (report: any) => void) => {
			const report = JSON.parse(readFileSync(path.join(root, EXAMPLE), "utf8"));
			edit(report);
			const file = path.join(scratch, "report.json");
			writeFileSync(file, JSON.stringify(report));
			return spawnSync(jsonschema, ["validate", path.join(root, REPORT_SCHEMA), file], { windowsHide: true }).status !== 0;
		};
		expect(refuses(() => {})).toBe(false);
		expect(refuses((report) => (report.verdict.reasons[0] = { code: "case_failed", bound: "callDeadline" }))).toBe(true);
		expect(refuses((report) => (report.verdict.reasons[0] = { code: "case_failed", caseId: "x", profile: "extism-kernel-v1" }))).toBe(true);
		expect(refuses((report) => (report.cases[0].outcome = "skipped"))).toBe(true);
		expect(refuses((report) => delete report.host.offering)).toBe(true);
		expect(refuses((report) => report.bounds.pop())).toBe(true);
		expect(refuses((report) => delete report.verdict)).toBe(true);
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
});
