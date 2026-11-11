// Checks the fixed controls of the WASM host qualification report in
// spec/mep/mck/wasm-host-report.controls.json against the verdict rule stated
// in spec/mep/mck/wasm-host-report.md, the corpus beside them and the
// execution profile contract.
//
// Usage (from the parent repository root):
//
//   bun run tools/check-wasm-host-report.ts     # or: mise run spec:mep-wasm-report-check
//
// The check fails when:
//
// 1. the rule's bound and profile orders, reason codes or outcomes differ from
//    the contract or from the published report schema;
// 2. a control names a case the corpus lacks, an element the rule lacks, or an
//    element another control already covers, or an element has no control;
// 3. the verdict or the refusals this file computes for a control differ from
//    the ones the control gives, or a control does not show the element it
//    covers;
// 4. the document does not state a reason code, a refusal code, a required
//    bound or a schema URL;
// 5. a schema is not a valid JSON Schema, or the controls or the abridged
//    example report do not validate against theirs.
//
// The verdict function here is a reference for the controls only. A runner's
// report check is implemented and tested in the runner's repository, against
// the same controls. This check runs no host and reads no host report.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const CONTROLS = "spec/mep/mck/wasm-host-report.controls.json";
export const DOCUMENT = "spec/mep/mck/wasm-host-report.md";
const SCHEMAS = "website/static/schemas/mep-wasm-host-kit/0.1.0-draft.1";
export const REPORT_SCHEMA = `${SCHEMAS}/report.schema.json`;
export const CONTROLS_SCHEMA = `${SCHEMAS}/report-controls.schema.json`;
export const EXAMPLE = "spec/mep/mck/fixtures/reports/abridged.report.json";
const SCHEMA_URL = "https://morphir.finos.org/schemas/mep-wasm-host-kit/0.1.0-draft.1";

export type Declaration = "enforced" | "not-enforced" | "inconsistent" | "undeclared";
export type Outcome = "passed" | "failed" | "error" | "refused" | "not_applicable" | "not_enforced";
const OUTCOMES: Outcome[] = ["passed", "failed", "error", "refused", "not_applicable", "not_enforced"];
const DECLARATIONS: Declaration[] = ["enforced", "not-enforced", "inconsistent", "undeclared"];

export interface Reason { code: string; bound?: string; caseId?: string; profile?: string }
export interface Verdict { qualified: boolean; reasons: Reason[] }
export interface Citation { profile: string; hostSha256: string }
interface Identity { [member: string]: string | null | undefined }
interface Host extends Identity { sha256: string | null; offering: string | null; platform: string | null; engine: string | null }
interface Base {
	runner: Identity;
	host: Omit<Host, "profiles"> & { profiles: string[] };
	bounds: Record<string, Declaration>;
	guestKitCitations: Citation[];
}
export interface Change {
	runner?: Identity;
	host?: Identity & { profiles?: string[] };
	bounds?: Record<string, Declaration>;
	guestKitCitations?: Citation[];
	corpusSha256?: string;
	outcomes?: Record<string, Outcome>;
	deviations?: string[];
	removeCases?: string[];
	duplicateCases?: string[];
	swapCases?: string[];
	storedTotals?: Record<string, number>;
	storedVerdict?: Verdict;
}
export interface Control {
	id: string;
	covers: string;
	says: string;
	change: Change;
	expect: Verdict | { rejected: string[] };
}
export interface Controls {
	$schema: string;
	corpus: string;
	contract: string;
	rule: { boundOrder: string[]; profileOrder: string[]; reasons: string[]; rejections: string[]; scenarios: string[] };
	base: Base;
	controls: Control[];
}
export interface CorpusCase { caseId: string; appliesTo: string; bounds?: string[] }
interface Contract {
	profiles: Record<string, { status: string }>;
	bounds: { requiredForQualification: string[]; optionalForQualification: string[] };
}
export interface ReportInput {
	controls: Controls;
	cases: CorpusCase[];
	corpusSha256: string;
	contract: Contract;
	document: string;
	reportSchema: { $defs: Record<string, { enum?: string[]; properties?: Record<string, { enum?: string[] }> }> };
}

/** A report, reduced to what the verdict rule and the refusals read. */
export interface Summary {
	runner: Identity;
	host: Identity & { profiles: string[] };
	bounds: Record<string, Declaration>;
	guestKitCitations: Citation[];
	corpusSha256: string;
	cases: { caseId: string; outcome: Outcome }[];
	totals: Record<string, number>;
	verdict: Verdict;
}

const TOTALS: [string, Outcome][] = [
	["passed", "passed"],
	["failed", "failed"],
	["error", "error"],
	["refused", "refused"],
	["notApplicable", "not_applicable"],
	["notEnforced", "not_enforced"],
];

/** The outcome of a case whose module is intact and whose runs all pass, given what the host declares. */
export function naturalOutcome(entry: CorpusCase, profiles: string[], bounds: Record<string, Declaration>): Outcome {
	if (!profiles.includes(entry.appliesTo)) return "not_applicable";
	const declared = (entry.bounds ?? []).map((bound) => bounds[bound]);
	if (declared.some((declaration) => declaration === "undeclared" || declaration === "inconsistent")) return "error";
	if (declared.includes("not-enforced")) return "not_enforced";
	return "passed";
}

/** Whether a recorded outcome can follow from the declarations. A missing or changed module file comes before the bounds. */
export function outcomeConsistent(natural: Outcome, outcome: Outcome): boolean {
	if (natural === "not_applicable" || outcome === "not_applicable") return natural === outcome;
	if (outcome === "refused" || outcome === "error") return true;
	if (natural === "error") return false;
	if (natural === "not_enforced") return outcome === "not_enforced";
	return outcome === "passed" || outcome === "failed";
}

export function countTotals(cases: { outcome: Outcome }[]): Record<string, number> {
	const totals: Record<string, number> = { cases: cases.length };
	for (const [member, outcome] of TOTALS) totals[member] = cases.filter((entry) => entry.outcome === outcome).length;
	return totals;
}

/** The verdict rule. `cases` are in the order the reasons follow. */
export function verdictOf(
	rule: Controls["rule"],
	required: string[],
	summary: Pick<Summary, "host" | "bounds" | "guestKitCitations" | "cases">,
): Verdict {
	const reasons: Reason[] = [];
	for (const bound of rule.boundOrder) {
		const declaration = summary.bounds[bound];
		if (declaration === "undeclared") reasons.push({ code: "bound_undeclared", bound });
		else if (declaration === "inconsistent") reasons.push({ code: "bound_inconsistent", bound });
		else if (declaration === "not-enforced" && required.includes(bound)) reasons.push({ code: "required_bound_not_enforced", bound });
	}
	for (const { caseId, outcome } of summary.cases) {
		if (outcome === "failed") reasons.push({ code: "case_failed", caseId });
		else if (outcome === "error") reasons.push({ code: "case_error", caseId });
		else if (outcome === "refused") reasons.push({ code: "case_refused", caseId });
	}
	for (const profile of rule.profileOrder) {
		if (!summary.host.profiles.includes(profile)) continue;
		const citation = summary.guestKitCitations.find((entry) => entry.profile === profile);
		if (!citation) reasons.push({ code: "guest_kit_missing", profile });
		else if (citation.hostSha256 !== summary.host.sha256) reasons.push({ code: "guest_kit_host_mismatch", profile });
	}
	return { qualified: reasons.length === 0, reasons };
}

const reasonKey = (reason: Reason) => JSON.stringify([reason.code, reason.bound ?? null, reason.caseId ?? null, reason.profile ?? null]);
export const sameVerdict = (left: Verdict, right: Verdict) =>
	left.qualified === right.qualified &&
	left.reasons.length === right.reasons.length &&
	left.reasons.every((reason, index) => {
		const other = right.reasons[index];
		return other !== undefined && reasonKey(reason) === reasonKey(other);
	});

/** The report a control describes: the base with the control's change applied. */
export function summarize(input: ReportInput, change: Change): Summary {
	const { base, rule } = input.controls;
	const runner = { ...base.runner, ...change.runner };
	const host = { ...base.host, ...change.host } as Summary["host"];
	const bounds = { ...base.bounds, ...change.bounds };
	const guestKitCitations = change.guestKitCitations ?? base.guestKitCitations;
	let cases = input.cases.map((entry) => ({
		caseId: entry.caseId,
		outcome: change.outcomes?.[entry.caseId] ?? naturalOutcome(entry, host.profiles, bounds),
	}));
	cases = cases.filter((entry) => !change.removeCases?.includes(entry.caseId));
	cases = cases.flatMap((entry) => (change.duplicateCases?.includes(entry.caseId) ? [entry, { ...entry }] : [entry]));
	if (change.swapCases) {
		const indexes = change.swapCases.map((caseId) => cases.findIndex((entry) => entry.caseId === caseId));
		const first = indexes[0] ?? -1;
		const second = indexes[1] ?? -1;
		const [left, right] = [cases[first], cases[second]];
		if (left && right) {
			cases[first] = right;
			cases[second] = left;
		}
	}
	const partial = { host, bounds, guestKitCitations, cases };
	return {
		runner,
		...partial,
		corpusSha256: change.corpusSha256 ?? input.corpusSha256,
		totals: { ...countTotals(cases), ...change.storedTotals },
		verdict: change.storedVerdict ?? verdictOf(rule, input.contract.bounds.requiredForQualification, partial),
	};
}

const present = (value: unknown) => typeof value === "string" && value.trim() !== "";

/** What a report check gives for a report: the refusals, or the recomputed verdict when there is none. */
export function checkSummary(input: ReportInput, summary: Summary): Verdict | { rejected: string[] } {
	const { rule } = input.controls;
	const profiles = Object.keys(input.contract.profiles);
	const found = new Set<string>();
	if (
		![summary.runner.name, summary.runner.version, summary.host.sha256, summary.host.offering, summary.host.platform, summary.host.engine].every(
			present,
		)
	) {
		found.add("identity_missing");
	}
	const declared = summary.host.profiles;
	if (
		declared.length === 0 ||
		new Set(declared).size !== declared.length ||
		declared.some((profile) => !profiles.includes(profile)) ||
		profiles.some((profile) => input.contract.profiles[profile]?.status === "required" && !declared.includes(profile))
	) {
		found.add("host_profiles");
	}
	if (summary.corpusSha256 !== input.corpusSha256) found.add("corpus_mismatch");
	if (summary.cases.map((entry) => entry.caseId).join("\n") !== input.cases.map((entry) => entry.caseId).join("\n")) {
		found.add("case_inventory");
	}
	const byId = new Map(input.cases.map((entry) => [entry.caseId, entry]));
	for (const { caseId, outcome } of summary.cases) {
		const entry = byId.get(caseId);
		if (entry && !outcomeConsistent(naturalOutcome(entry, declared, summary.bounds), outcome)) found.add("outcome_inconsistent");
	}
	const counted = countTotals(summary.cases);
	if (Object.keys(counted).some((member) => counted[member] !== summary.totals[member])) found.add("totals_mismatch");
	const cited = summary.guestKitCitations.map((citation) => citation.profile);
	if (new Set(cited).size !== cited.length || cited.some((profile) => !declared.includes(profile))) found.add("citation_invalid");
	const verdict = verdictOf(rule, input.contract.bounds.requiredForQualification, summary);
	if (!sameVerdict(verdict, summary.verdict)) found.add("verdict_mismatch");
	const rejected = rule.rejections.filter((code) => found.has(code));
	return rejected.length > 0 ? { rejected } : verdict;
}

const sameList = (left: string[], right: string[]) => left.length === right.length && left.every((value, index) => value === right[index]);
const sameSet = (left: string[], right: string[]) => sameList([...left].sort(), [...right].sort());

/** Statements of the rule that the document must carry. */
export function documentProblems(input: ReportInput): string[] {
	const { rule } = input.controls;
	const failures: string[] = [];
	const states = (text: string, what: string) => {
		if (!input.document.includes(text)) failures.push(`${DOCUMENT}: the document does not state ${what}, ${text}`);
	};
	for (const code of rule.reasons) states(`\`${code}\``, "the reason code");
	for (const code of rule.rejections) states(`\`${code}\``, "the refusal code");
	for (const bound of input.contract.bounds.requiredForQualification) states(`\`${bound}\``, "the required bound");
	for (const outcome of OUTCOMES) states(`\`${outcome}\``, "the outcome");
	states(`${SCHEMA_URL}/report.schema.json`, "the report schema URL");
	states(`${SCHEMA_URL}/report-controls.schema.json`, "the controls schema URL");
	return failures;
}

export function checkControls(input: ReportInput): string[] {
	const { controls, contract } = input;
	const { rule, base } = controls;
	const failures: string[] = [];
	const fail = (message: string) => failures.push(`${CONTROLS}: ${message}`);

	const contractBounds = [...contract.bounds.requiredForQualification, ...contract.bounds.optionalForQualification];
	if (!sameSet(rule.boundOrder, contractBounds)) fail(`rule.boundOrder must hold the contract's bounds, ${contractBounds.join(", ")}`);
	const requiredFirst = Object.keys(contract.profiles).sort(
		(left, right) => Number(contract.profiles[right]?.status === "required") - Number(contract.profiles[left]?.status === "required"),
	);
	if (!sameList(rule.profileOrder, requiredFirst)) fail(`rule.profileOrder must be the contract's profiles, required first: ${requiredFirst.join(", ")}`);
	const schemaReasons = input.reportSchema.$defs.reason?.properties?.code?.enum ?? [];
	if (!sameList(rule.reasons, schemaReasons)) fail(`rule.reasons must equal the reason codes of ${REPORT_SCHEMA}, in order`);
	for (const [name, expected] of [
		["bound", rule.boundOrder],
		["profile", rule.profileOrder],
	] as const) {
		if (!sameList(input.reportSchema.$defs[name]?.enum ?? [], expected)) fail(`${REPORT_SCHEMA} must list the ${name}s in the rule's order`);
	}
	if (!sameSet(Object.keys(base.bounds), rule.boundOrder)) fail("base.bounds must declare each bound once");

	const elements = [...rule.reasons, ...rule.rejections, ...rule.scenarios];
	if (new Set(elements).size !== elements.length) fail("a reason, refusal and scenario name must be unique across the rule");
	const caseIds = new Set(input.cases.map((entry) => entry.caseId));
	const ids = new Set<string>();
	const covered = new Map<string, string>();
	for (const control of controls.controls) {
		const at = `control ${control.id}`;
		if (ids.has(control.id)) fail(`${at}: the id is used twice`);
		ids.add(control.id);
		if (!elements.includes(control.covers)) fail(`${at}: covers ${control.covers}, which the rule does not name`);
		else if (covered.has(control.covers)) fail(`${at}: covers ${control.covers}, which ${covered.get(control.covers)} already covers`);
		else covered.set(control.covers, control.id);

		const { change } = control;
		const named = [
			...Object.keys(change.outcomes ?? {}),
			...(change.deviations ?? []),
			...(change.removeCases ?? []),
			...(change.duplicateCases ?? []),
			...(change.swapCases ?? []),
		];
		for (const caseId of named) if (!caseIds.has(caseId)) fail(`${at}: the corpus has no case ${caseId}`);
		for (const [bound, declaration] of Object.entries(change.bounds ?? {})) {
			if (!rule.boundOrder.includes(bound) || !DECLARATIONS.includes(declaration)) fail(`${at}: ${bound} ${declaration} is not a bound declaration`);
		}
		for (const outcome of Object.values(change.outcomes ?? {})) if (!OUTCOMES.includes(outcome)) fail(`${at}: ${outcome} is not an outcome`);

		const expected = control.expect;
		const computed = checkSummary(input, summarize(input, change));
		if ("rejected" in expected) {
			for (const code of expected.rejected) if (!rule.rejections.includes(code)) fail(`${at}: expects the refusal ${code}, which the rule does not name`);
			if (!("rejected" in computed)) fail(`${at}: expects the refusals ${expected.rejected.join(", ")}, and the rule gives a verdict`);
			else if (!sameList(computed.rejected, expected.rejected)) {
				fail(`${at}: expects the refusals ${expected.rejected.join(", ")}, and the rule gives ${computed.rejected.join(", ")}`);
			}
			if (rule.rejections.includes(control.covers) && !expected.rejected.includes(control.covers)) fail(`${at}: does not show the refusal it covers`);
			if (!rule.rejections.includes(control.covers)) fail(`${at}: expects a refusal and covers ${control.covers}, which is not one`);
		} else {
			for (const reason of expected.reasons) if (!rule.reasons.includes(reason.code)) fail(`${at}: expects the reason ${reason.code}, which the rule does not name`);
			if (expected.qualified !== (expected.reasons.length === 0)) fail(`${at}: a verdict is qualified exactly when it has no reason`);
			if ("rejected" in computed) fail(`${at}: expects a verdict, and the rule refuses the report with ${computed.rejected.join(", ")}`);
			else if (!sameVerdict(computed, expected)) {
				fail(`${at}: expects ${JSON.stringify(expected)}, and the rule gives ${JSON.stringify(computed)}`);
			}
			if (rule.reasons.includes(control.covers) && !expected.reasons.some((reason) => reason.code === control.covers)) {
				fail(`${at}: does not show the reason it covers`);
			}
			if (rule.rejections.includes(control.covers)) fail(`${at}: covers the refusal ${control.covers} and expects a verdict`);
			if (control.covers.startsWith("qualified") && !expected.qualified) fail(`${at}: covers ${control.covers} and expects a host that is not qualified`);
		}
	}
	for (const element of elements) if (!covered.has(element)) fail(`no control covers ${element}`);
	return [...failures, ...documentProblems(input)];
}

export function loadReportInput(root: string): ReportInput {
	const read = (relative: string) => readFileSync(path.join(root, relative));
	const controls = JSON.parse(read(CONTROLS).toString("utf8")) as Controls;
	const directory = path.posix.dirname(CONTROLS);
	const corpusPath = path.posix.join(directory, controls.corpus);
	const corpusBytes = read(corpusPath);
	return {
		controls,
		cases: (JSON.parse(corpusBytes.toString("utf8")) as { cases: CorpusCase[] }).cases,
		corpusSha256: createHash("sha256").update(corpusBytes).digest("hex"),
		contract: JSON.parse(read(path.posix.join(directory, controls.contract)).toString("utf8")) as Contract,
		document: read(DOCUMENT).toString("utf8"),
		reportSchema: JSON.parse(read(REPORT_SCHEMA).toString("utf8")) as ReportInput["reportSchema"],
	};
}

/** Runs the JSON Schema CLI: both schemas against the metaschema, and the controls and the example report against theirs. */
export function schemaProblems(root: string): string[] {
	const run = (args: string[]) =>
		spawnSync(process.env.MORPHIR_JSONSCHEMA ?? "jsonschema", args, { cwd: root, encoding: "utf8", windowsHide: true });
	const failures: string[] = [];
	for (const args of [
		["metaschema", REPORT_SCHEMA, CONTROLS_SCHEMA],
		["validate", CONTROLS_SCHEMA, CONTROLS],
		["validate", REPORT_SCHEMA, EXAMPLE],
	]) {
		const result = run(args);
		if (result.error) failures.push(`jsonschema ${args[0]} could not run: ${result.error.message}`);
		else if (result.status !== 0) failures.push(`jsonschema ${args.join(" ")} failed:\n${result.stdout}${result.stderr}`.trimEnd());
	}
	return failures;
}

function main(): void {
	const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
	for (const file of [CONTROLS, DOCUMENT, REPORT_SCHEMA, CONTROLS_SCHEMA, EXAMPLE]) {
		if (!existsSync(path.join(root, file))) {
			console.error(`Missing ${file}`);
			process.exit(1);
		}
	}
	const input = loadReportInput(root);
	const failures = [...checkControls(input), ...schemaProblems(root)];
	if (failures.length > 0) {
		console.error(failures.join("\n"));
		console.error(`\nThe WASM host report controls have ${failures.length} failures.`);
		process.exit(1);
	}
	const { rule, controls } = input.controls;
	console.error(
		`WASM host report: ${controls.length} controls cover ${rule.reasons.length} reasons, ${rule.rejections.length} refusals and ${rule.scenarios.length} scenarios over ${input.cases.length} cases.`,
	);
}

if (import.meta.main) main();
