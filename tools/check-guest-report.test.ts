// Tests for the MEP guest report controls check. Run with:
//   bun test tools/check-guest-report.test.ts
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
	expectedKind,
	type GuestInput,
	loadGuestInput,
	mergePatch,
	planOf,
	REPORT_SCHEMA,
	schemaProblems,
	select,
	summarize,
} from "./check-guest-report";

const root = path.resolve(import.meta.dir, "..");
const input = loadGuestInput(root);
const { rule, base } = input.controls;
const jsonschema = process.env.MORPHIR_JSONSCHEMA ?? "jsonschema";
const hasCli = spawnSync(jsonschema, ["--version"], { windowsHide: true }).status === 0;

function failuresAfter(change: (controls: Controls, copy: GuestInput) => void): string[] {
	const copy: GuestInput = { ...input, controls: structuredClone(input.controls) };
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
		expect(failures).toContain(`spec/mep/mck/guest-report.controls.json: no control covers ${control.covers}`);
	}
});

test("a control with another result than the rule gives fails", () => {
	const failures = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "legacy-only-guest");
		if (control && "reasons" in control.expect) control.expect = { qualified: true, reasons: [], cases: 1 };
	});
	expect(failures.some((failure) => failure.includes("control legacy-only-guest: expects"))).toBe(true);
	const refusals = failuresAfter((controls) => {
		const control = controls.controls.find((entry) => entry.id === "claim-edited");
		if (control) control.expect = { rejected: ["case_inventory"] };
	});
	expect(refusals.some((failure) => failure.includes("control claim-edited: expects the refusals case_inventory"))).toBe(true);
});

test("the plan of a claim with both, one and no IR versions", () => {
	const both = select(rule, input.kitLanguages, base.claim);
	expect(both).toEqual({ language: "python", irVersions: ["3.0.0", "4.0.0"] });
	const plan = planOf(rule, both);
	expect(plan.length).toBe(21);
	expect(plan.slice(0, 5)).toEqual(["describe", "model-initialize", "model-initialized-silent", "unknown-notification-silent", "compile-model-vthree"]);
	expect(plan.slice(-7)).toEqual(["bad-digest", "malformed-source", "unknown-method", "describe-immutable", "model-shutdown", "after-shutdown", "model-exit"]);
	const four = mergePatch(base.claim, { capabilities: { frontend: { irVersions: ["4.0.0"] } } });
	expect(planOf(rule, select(rule, input.kitLanguages, four)).length).toBe(16);
	expect(planOf(rule, select(rule, input.kitLanguages, mergePatch(base.claim, { protocolVersions: ["0.1"] })))).toEqual(["describe"]);
});

test("the language is the first kit language claimed both ways, in lexical order", () => {
	const claim = mergePatch(base.claim, {
		capabilities: {
			frontend: { languages: [{ id: "python" }, { id: "morphir-fixture-flags" }, { id: "gleam" }] },
			backend: { targets: ["python", "morphir-fixture-flags"] },
		},
	});
	expect(select(rule, input.kitLanguages, claim)?.language).toBe("morphir-fixture-flags");
	const none = mergePatch(base.claim, { capabilities: { backend: { targets: ["rust"] } } });
	expect(select(rule, input.kitLanguages, none)).toBeNull();
});

test("the compile and generate flags are not required", () => {
	const claim = mergePatch(base.claim, { capabilities: { frontend: { compile: false }, backend: { generate: false } } });
	expect(select(rule, input.kitLanguages, claim)?.irVersions).toEqual(["3.0.0", "4.0.0"]);
});

test("the observation each case expects", () => {
	expect(expectedKind("model-initialized-silent")).toBe("silent");
	expect(expectedKind("unknown-notification-silent")).toBe("silent");
	expect(expectedKind("model-exit")).toBe("exit");
	expect(expectedKind("after-shutdown")).toBe("response");
});

test("a passed case with the wrong observation, and a stop with no failure, are inconsistent", () => {
	const wrongKind = summarize(input, {});
	const entry = wrongKind.cases.find((value) => value.caseId === "model-initialized-silent");
	if (entry) entry.kind = "response";
	expect(checkSummary(input, wrongKind)).toEqual({ rejected: ["outcome_inconsistent"] });
	const failedWithWrongKind = summarize(input, { outcomes: { "model-initialized-silent": "failed" } });
	const failedEntry = failedWithWrongKind.cases.find((value) => value.caseId === "model-initialized-silent");
	if (failedEntry) failedEntry.kind = "incomplete";
	expect("rejected" in checkSummary(input, failedWithWrongKind)).toBe(false);
	expect(checkSummary(input, summarize(input, { outcomes: { "model-exit": "not_run" } }))).toEqual({ rejected: ["outcome_inconsistent"] });
});

test("a removed host identity and a removed case give both refusals in order", () => {
	expect(checkSummary(input, summarize(input, { runner: { name: null }, removeCases: ["bad-digest"] }))).toEqual({
		rejected: ["identity_missing", "case_inventory"],
	});
});

test("the document must state every code and case", () => {
	const failures = failuresAfter((_, copy) => {
		copy.document = copy.document.replaceAll("`comparison_mismatch`", "");
	});
	expect(failures).toContain("spec/mep/mck/guest-report.md: the document does not state the code, `comparison_mismatch`");
});

test.skipIf(!hasCli)("the schemas are valid and the controls and the example validate", () => {
	expect(schemaProblems(root)).toEqual([]);
});

test.skipIf(!hasCli)("the report schema refuses wrong observations and verdicts", () => {
	const scratch = mkdtempSync(path.join(tmpdir(), "guest-report-"));
	try {
		const refuses = (edit: (report: any) => void) => {
			const report = JSON.parse(readFileSync(path.join(root, EXAMPLE), "utf8"));
			edit(report);
			const file = path.join(scratch, "report.json");
			writeFileSync(file, JSON.stringify(report));
			return spawnSync(jsonschema, ["validate", path.join(root, REPORT_SCHEMA), file], { windowsHide: true }).status !== 0;
		};
		expect(refuses(() => {})).toBe(false);
		expect(refuses((report) => (report.cases[0].observed = { kind: "silent", message: {} }))).toBe(true);
		expect(refuses((report) => (report.cases[0].observed = { kind: "incomplete", reason: "crashed" }))).toBe(true);
		expect(refuses((report) => (report.cases[0].outcome = "skipped"))).toBe(true);
		expect(refuses((report) => (report.verdict.reasons[0].code = "guest_kit_missing"))).toBe(true);
		expect(refuses((report) => (report.plan = { language: "python", irVersions: ["2.0.0"] }))).toBe(true);
		expect(refuses((report) => (report.artifacts = []))).toBe(true);
		expect(refuses((report) => (report.suite.profile = "python-json-library-v1"))).toBe(true);
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
});
