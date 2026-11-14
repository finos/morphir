// Checks the fixed controls of the MEP guest kit report in
// spec/mep/mck/guest-report.controls.json against the plan, outcome and
// verdict rules stated in spec/mep/mck/guest-report.md and the kit file
// beside them.
//
// Usage (from the parent repository root):
//
//   bun run tools/check-guest-report.ts     # or: mise run spec:mep-guest-report-check
//
// The check fails when:
//
// 1. the rule's case lists differ from the single-session plan the document
//    states, or a reason or refusal has no matching statement in the document;
// 2. a control names a case the plan lacks where it must be planned, an element
//    the rule lacks, or an element another control already covers, or an
//    element has no control;
// 3. the verdict or refusals this file computes for a control differ from the
//    ones it gives, or a control does not show the element it covers;
// 4. a schema is not a valid JSON Schema, or the controls or the abridged
//    example report do not validate against theirs.
//
// The functions here are a reference for the controls only. They rebuild the
// plan and check outcomes that follow without a comparison. Rebuilding each
// request and recomputing each comparison is the runner's report check, in the
// runner's repository. This check runs no guest and reads no real report.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const CONTROLS = "spec/mep/mck/guest-report.controls.json";
export const DOCUMENT = "spec/mep/mck/guest-report.md";
export const EXAMPLE = "spec/mep/mck/fixtures/reports/guest-abridged.report.json";
const SCHEMAS = "website/static/schemas/mep-guest-kit/0.1.0-draft.1";
export const REPORT_SCHEMA = `${SCHEMAS}/report.schema.json`;
export const CONTROLS_SCHEMA = `${SCHEMAS}/report-controls.schema.json`;
const SCHEMA_URL = "https://morphir.finos.org/schemas/mep-guest-kit/0.1.0-draft.1";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };
export type Outcome = "passed" | "failed" | "not_run";
export type Kind = "response" | "silent" | "exit" | "incomplete";
export type Delivery = "delivered" | "withheld" | "unknown";
export interface Reason { code: string; caseId: string }
export interface Verdict { qualified: boolean; reasons: Reason[] }
export interface Plan { language: string; irVersions: string[] }
export interface Rule {
	protocol: string;
	irVersions: string[];
	fixedBefore: string[];
	perVersion: string[];
	versionSuffixes: Record<string, string>;
	fixedAfter: string[];
	reasons: string[];
	rejections: string[];
	runnerRejections: string[];
	scenarios: string[];
}
export interface Change {
	claimPatch?: JsonObject;
	editRecordedClaim?: JsonObject;
	recordedPlan?: Plan | null;
	runner?: Record<string, string | null>;
	host?: Record<string, string | null>;
	suiteSha256?: string;
	outcomes?: Record<string, Outcome>;
	stopAfter?: string;
	removeCases?: string[];
	addCases?: { after: string; caseId: string }[];
	swapCases?: string[];
	storedTotals?: Record<string, number>;
	storedVerdict?: Verdict;
	advertisesCall?: boolean;
	deliveries?: Record<string, Delivery>;
	unmatched?: { duringCase: string }[];
}
export interface Control {
	id: string;
	covers: string;
	says: string;
	change: Change;
	expect: (Verdict & { cases: number }) | { rejected: string[] };
}
export interface Controls {
	$schema: string;
	kit: string;
	rule: Rule;
	base: { runner: Record<string, string>; host: Record<string, Json>; artifacts: { path: string; sha256: string }[]; claim: JsonObject };
	controls: Control[];
}
export interface GuestInput {
	controls: Controls;
	kitLanguages: string[];
	kitSha256: string;
	document: string;
}
export interface RecordedCase { caseId: string; outcome: Outcome; kind: Kind | null; delivery?: Delivery | null }
export interface Summary {
	runner: Record<string, string | null | undefined>;
	host: Record<string, Json | undefined>;
	artifacts: { path: string; sha256: string }[];
	suiteSha256: string;
	recordedClaim: Json;
	plan: Plan | null;
	advertisesCall: boolean;
	cases: RecordedCase[];
	unmatched: { duringCase: string }[];
	totals: Record<string, number>;
	verdict: Verdict;
}

const isObject = (value: Json | undefined): value is JsonObject => typeof value === "object" && value !== null && !Array.isArray(value);
const member = (value: Json | undefined, name: string): Json | undefined => (isObject(value) ? value[name] : undefined);
const list = (value: Json | undefined): Json[] => (Array.isArray(value) ? value : []);

/** RFC 7386 JSON merge patch. */
export function mergePatch(target: Json, patch: Json): Json {
	if (!isObject(patch)) return structuredClone(patch);
	const result: JsonObject = isObject(target) ? structuredClone(target) : {};
	for (const [key, value] of Object.entries(patch)) {
		if (value === null) delete result[key];
		else result[key] = mergePatch(result[key] ?? null, value);
	}
	return result;
}

const claimsVersion = (versions: Json | undefined, full: string) =>
	list(versions).some((value) => value === full || value === full.split(".")[0]);

const jsonTuple = (operation: string, irVersion: string) => ({
	operation,
	profile: "morphir-ir",
	codec: "morphir-json",
	envelopeVersion: "0.1.0-draft.1",
	irVersion,
});
const sameJson = (left: unknown, right: unknown): boolean => JSON.stringify(sortKeys(left)) === JSON.stringify(sortKeys(right));
function sortKeys(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(sortKeys);
	if (typeof value === "object" && value !== null) {
		return Object.fromEntries(Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => [k, sortKeys(v)]));
	}
	return value;
}

/** What a describe claim selects, or null when it selects nothing. */
export function select(rule: Rule, kitLanguages: string[], claim: Json): Plan | null {
	if (!list(member(claim, "protocolVersions")).includes(rule.protocol)) return null;
	const capabilities = member(claim, "capabilities");
	const frontend = member(capabilities, "frontend");
	const backend = member(capabilities, "backend");
	const claimed = list(member(frontend, "languages"));
	const targets = list(member(backend, "targets"));
	const language = [...kitLanguages]
		.sort()
		.find((id) => claimed.some((entry) => member(entry, "id") === id) && targets.includes(id));
	if (!language) return null;
	const tuples = list(member(member(capabilities, "modelTransport"), "tuples"));
	const has = (tuple: object) => tuples.some((entry) => sameJson(entry, tuple));
	const irVersions = rule.irVersions.filter(
		(version) =>
			claimsVersion(member(frontend, "irVersions"), version) &&
			claimsVersion(member(backend, "irVersions"), version) &&
			has(jsonTuple("morphir.frontend.compileModel", version)) &&
			has(jsonTuple("morphir.backend.generateModel", version)),
	);
	return irVersions.length > 0 ? { language, irVersions } : null;
}

/** The planned case ids, in order. */
export function planOf(rule: Rule, plan: Plan | null): string[] {
	if (!plan) return ["describe"];
	return [
		...rule.fixedBefore,
		...plan.irVersions.flatMap((version) => rule.perVersion.map((base) => `${base}-${rule.versionSuffixes[version]}`)),
		...rule.fixedAfter,
	];
}

/** The observation a case expects. */
export function expectedKind(caseId: string): Kind {
	if (caseId.endsWith("-silent")) return "silent";
	if (caseId === "model-exit") return "exit";
	return "response";
}

export function countTotals(cases: RecordedCase[]): Record<string, number> {
	return {
		cases: cases.length,
		passed: cases.filter((entry) => entry.outcome === "passed").length,
		failed: cases.filter((entry) => entry.outcome === "failed").length,
		notRun: cases.filter((entry) => entry.outcome === "not_run").length,
	};
}

export function verdictOf(cases: RecordedCase[]): Verdict {
	const reasons: Reason[] = [];
	for (const { caseId, outcome } of cases) {
		if (outcome === "failed") reasons.push({ code: "case_failed", caseId });
		else if (outcome === "not_run") reasons.push({ code: "case_not_run", caseId });
	}
	return { qualified: reasons.length === 0, reasons };
}

/** The report a control describes. */
export function summarize(input: GuestInput, change: Change): Summary {
	const { base, rule } = input.controls;
	const claim = mergePatch(base.claim, change.claimPatch ?? {});
	const selected = select(rule, input.kitLanguages, claim);
	let cases: RecordedCase[] = planOf(rule, selected).map((caseId) => ({
		caseId,
		outcome: caseId === "describe" && !selected ? "failed" : "passed",
		kind: expectedKind(caseId),
		...(expectedKind(caseId) === "silent" ? { delivery: change.advertisesCall ? "delivered" : "withheld" } : {}),
	}));
	for (const entry of cases) {
		const delivery = change.deliveries?.[entry.caseId];
		if (delivery) entry.delivery = delivery;
	}
	for (const entry of cases) {
		const outcome = change.outcomes?.[entry.caseId];
		if (outcome) Object.assign(entry, { outcome, kind: outcome === "not_run" ? null : entry.kind }, outcome === "not_run" && "delivery" in entry ? { delivery: null } : {});
	}
	if (change.stopAfter) {
		const at = cases.findIndex((entry) => entry.caseId === change.stopAfter);
		cases = cases.map((entry, index) =>
			index === at ? { ...entry, outcome: "failed" } : index > at && at >= 0 ? { ...entry, outcome: "not_run", kind: null, ...("delivery" in entry ? { delivery: null } : {}) } : entry,
		);
	}
	cases = cases.filter((entry) => !change.removeCases?.includes(entry.caseId));
	for (const added of change.addCases ?? []) {
		const at = cases.findIndex((entry) => entry.caseId === added.after);
		cases.splice(at + 1, 0, { caseId: added.caseId, outcome: "passed", kind: "response" });
	}
	if (change.swapCases) {
		const [first, second] = change.swapCases.map((caseId) => cases.findIndex((entry) => entry.caseId === caseId));
		const left = first === undefined ? undefined : cases[first];
		const right = second === undefined ? undefined : cases[second];
		if (left && right && first !== undefined && second !== undefined) {
			cases[first] = right;
			cases[second] = left;
		}
	}
	return {
		runner: { ...base.runner, ...change.runner },
		host: { ...base.host, ...change.host },
		artifacts: base.artifacts,
		suiteSha256: change.suiteSha256 ?? input.kitSha256,
		recordedClaim: mergePatch(claim, change.editRecordedClaim ?? {}),
		plan: change.recordedPlan === undefined ? selected : change.recordedPlan,
		advertisesCall: change.advertisesCall ?? false,
		cases,
		unmatched: change.unmatched ?? [],
		totals: { ...countTotals(cases), ...change.storedTotals },
		verdict: change.storedVerdict ?? verdictOf(cases),
	};
}

const present = (value: unknown) => typeof value === "string" && value.trim() !== "";
const sameVerdict = (left: Verdict, right: Verdict) => sameJson(left, right);

/** The refusals of a report, or its recomputed verdict when there is none. */
export function checkSummary(input: GuestInput, summary: Summary): Verdict | { rejected: string[] } {
	const { rule } = input.controls;
	const found = new Set<string>();
	if (
		![summary.runner.name, summary.runner.version, summary.host.executable, summary.host.sha256].every(present) ||
		summary.artifacts.length === 0
	) {
		found.add("identity_missing");
	}
	if (summary.suiteSha256 !== input.kitSha256) found.add("kit_mismatch");
	const selected = select(rule, input.kitLanguages, summary.recordedClaim);
	if (!sameJson(summary.plan, selected)) found.add("plan_mismatch");
	const planned = planOf(rule, selected);
	if (summary.cases.map((entry) => entry.caseId).join("\n") !== planned.join("\n")) found.add("case_inventory");
	const firstNotRun = summary.cases.findIndex((entry) => entry.outcome === "not_run");
	const consistent = summary.cases.every((entry, index) => {
		if (entry.outcome === "not_run") return entry.kind === null;
		if (entry.kind === null) return false;
		if (firstNotRun >= 0 && index > firstNotRun) return false;
		if (entry.kind !== expectedKind(entry.caseId) && entry.outcome !== "failed") return false;
		if (entry.caseId === "describe" && !selected && entry.outcome !== "failed") return false;
		if (expectedKind(entry.caseId) === "silent" && entry.outcome === "passed") {
			if (entry.delivery !== "delivered" && !(entry.delivery === "withheld" && !summary.advertisesCall)) return false;
		}
		return true;
	});
	const unmatchedConsistent = summary.unmatched.every(({ duringCase }) =>
		summary.cases.some((entry) => entry.caseId === duringCase && entry.outcome === "failed"),
	);
	const failedBeforeStop = firstNotRun < 0 || summary.cases.slice(0, firstNotRun).some((entry) => entry.outcome === "failed");
	if (!consistent || !failedBeforeStop || !unmatchedConsistent) found.add("outcome_inconsistent");
	const counted = countTotals(summary.cases);
	if (Object.keys(counted).some((key) => counted[key] !== summary.totals[key])) found.add("totals_mismatch");
	const verdict = verdictOf(summary.cases);
	if (!sameVerdict(verdict, summary.verdict)) found.add("verdict_mismatch");
	const rejected = rule.rejections.filter((code) => found.has(code));
	return rejected.length > 0 ? { rejected } : verdict;
}

const sameList = (left: string[], right: string[]) => left.length === right.length && left.every((value, index) => value === right[index]);

export function documentProblems(input: GuestInput): string[] {
	const { rule } = input.controls;
	const failures: string[] = [];
	const states = (text: string, what: string) => {
		if (!input.document.includes(text)) failures.push(`${DOCUMENT}: the document does not state ${what}, ${text}`);
	};
	for (const code of [...rule.reasons, ...rule.rejections, ...rule.runnerRejections]) states(`\`${code}\``, "the code");
	for (const caseId of [...rule.fixedBefore, ...rule.perVersion, ...rule.fixedAfter]) states(`\`${caseId}\``, "the case");
	for (const kind of ["response", "silent", "exit", "incomplete"]) states(`\`${kind}\``, "the observation kind");
	for (const delivery of ["delivered", "withheld", "unknown"]) states(`\`${delivery}\``, "the delivery");
	states(`${SCHEMA_URL}/report.schema.json`, "the report schema URL");
	states(`${SCHEMA_URL}/report-controls.schema.json`, "the controls schema URL");
	return failures;
}

export function checkControls(input: GuestInput): string[] {
	const { rule } = input.controls;
	const failures: string[] = [];
	const fail = (message: string) => failures.push(`${CONTROLS}: ${message}`);
	const fixed = rule.fixedBefore.length + rule.fixedAfter.length;
	if (fixed !== 11 || rule.perVersion.length !== 5) fail("the rule must have 11 fixed cases and 5 per IR version");
	if (!sameList(Object.keys(rule.versionSuffixes), rule.irVersions)) fail("rule.versionSuffixes must name each IR version, in order");
	const elements = [...rule.reasons, ...rule.rejections, ...rule.scenarios];
	if (new Set(elements).size !== elements.length) fail("a reason, refusal and scenario name must be unique across the rule");
	const covered = new Map<string, string>();
	const ids = new Set<string>();
	for (const control of input.controls.controls) {
		const at = `control ${control.id}`;
		if (ids.has(control.id)) fail(`${at}: the id is used twice`);
		ids.add(control.id);
		if (!elements.includes(control.covers)) fail(`${at}: covers ${control.covers}, which the rule does not name`);
		else if (covered.has(control.covers)) fail(`${at}: covers ${control.covers}, which ${covered.get(control.covers)} already covers`);
		else covered.set(control.covers, control.id);

		const summary = summarize(input, control.change);
		const planned = new Set(planOf(rule, select(rule, input.kitLanguages, mergePatch(input.controls.base.claim, control.change.claimPatch ?? {}))));
		const named = [
			...Object.keys(control.change.outcomes ?? {}),
			...(control.change.removeCases ?? []),
			...(control.change.swapCases ?? []),
			...(control.change.addCases ?? []).map((added) => added.after),
			...(control.change.stopAfter ? [control.change.stopAfter] : []),
			...Object.keys(control.change.deliveries ?? {}),
			...(control.change.unmatched ?? []).map((entry) => entry.duringCase),
		];
		for (const caseId of named) if (!planned.has(caseId) && !(control.change.addCases ?? []).some((added) => added.caseId === caseId)) fail(`${at}: the plan has no case ${caseId}`);

		const expected = control.expect;
		const computed = checkSummary(input, summary);
		if ("rejected" in expected) {
			for (const code of expected.rejected) if (!rule.rejections.includes(code)) fail(`${at}: expects the refusal ${code}, which the rule does not name`);
			if (!("rejected" in computed)) fail(`${at}: expects the refusals ${expected.rejected.join(", ")}, and the rule gives a verdict`);
			else if (!sameList(computed.rejected, expected.rejected)) fail(`${at}: expects the refusals ${expected.rejected.join(", ")}, and the rule gives ${computed.rejected.join(", ")}`);
			if (rule.rejections.includes(control.covers) && !expected.rejected.includes(control.covers)) fail(`${at}: does not show the refusal it covers`);
			if (rule.reasons.includes(control.covers)) fail(`${at}: covers the reason ${control.covers} and expects a refusal`);
		} else {
			if (expected.qualified !== (expected.reasons.length === 0)) fail(`${at}: a verdict is qualified exactly when it has no reason`);
			if (summary.cases.length !== expected.cases) fail(`${at}: expects ${expected.cases} cases, and the plan has ${summary.cases.length}`);
			if ("rejected" in computed) fail(`${at}: expects a verdict, and the rule refuses the report with ${computed.rejected.join(", ")}`);
			else if (!sameVerdict(computed, { qualified: expected.qualified, reasons: expected.reasons })) {
				fail(`${at}: expects ${JSON.stringify({ qualified: expected.qualified, reasons: expected.reasons })}, and the rule gives ${JSON.stringify(computed)}`);
			}
			if (rule.reasons.includes(control.covers) && !expected.reasons.some((reason) => reason.code === control.covers)) fail(`${at}: does not show the reason it covers`);
			if (rule.rejections.includes(control.covers)) fail(`${at}: covers the refusal ${control.covers} and expects a verdict`);
			if (control.covers.startsWith("qualified") && !expected.qualified) fail(`${at}: covers ${control.covers} and expects a guest that is not qualified`);
		}
	}
	for (const element of elements) if (!covered.has(element)) fail(`no control covers ${element}`);
	return [...failures, ...documentProblems(input)];
}

export function loadGuestInput(root: string): GuestInput {
	const read = (relative: string) => readFileSync(path.join(root, relative));
	const controls = JSON.parse(read(CONTROLS).toString("utf8")) as Controls;
	const kitPath = path.posix.join(path.posix.dirname(CONTROLS), controls.kit);
	const kitBytes = read(kitPath);
	const kit = JSON.parse(kitBytes.toString("utf8")) as { languages: Record<string, unknown> };
	return {
		controls,
		kitLanguages: Object.keys(kit.languages),
		kitSha256: createHash("sha256").update(kitBytes).digest("hex"),
		document: read(DOCUMENT).toString("utf8"),
	};
}

export function schemaProblems(root: string): string[] {
	const run = (args: string[]) => spawnSync(process.env.MORPHIR_JSONSCHEMA ?? "jsonschema", args, { cwd: root, encoding: "utf8", windowsHide: true });
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
	const input = loadGuestInput(root);
	const failures = [...checkControls(input), ...schemaProblems(root)];
	if (failures.length > 0) {
		console.error(failures.join("\n"));
		console.error(`\nThe MEP guest report controls have ${failures.length} failures.`);
		process.exit(1);
	}
	const { rule, controls } = input.controls;
	console.error(
		`MEP guest report: ${controls.length} controls cover ${rule.reasons.length} reasons, ${rule.rejections.length} refusals and ${rule.scenarios.length} scenarios.`,
	);
}

if (import.meta.main) main();
