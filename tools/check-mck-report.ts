// Adjudicates a Morphir Compatibility Kit run against the list of cases the
// binding under test is allowed to fail.
//
//   bun run tools/check-mck-report.ts <report.json> <allowed-failing.json>
//
// This checker does not run the kit — a `mck:run-*` task does, and writes the
// driver's report first. What happens here is the adjudication: the set of case
// ids with any failing record has to equal the `cases` array in the binding's
// allowed-failing list, in both directions. A new failure is a regression; a
// listed case that has started passing is a stale entry, and leaving it in would
// hide the next real failure behind it.
//
// The report's shape is `report.schema.json` in the kit (spec/ir/mck), contract
// version 1: a `records` array of `{ caseId, irVersion, profile, role,
// fenceIndex, path?, result, durationMs, message? }`, where `result` is one of
// `pass`, `fail`, `skipped` and `kit-error`. One case has many records — one per
// fence per path — so a case is failing if any of its records is.
//
// A run with nothing failing is not the same as a run that proved anything, so
// two further things are checked. At least one record has to have passed — a
// report of nothing but skips would otherwise satisfy an empty allow-list. And
// every skip has to be one the binding asked for: the driver skips a fence only
// for a capability the adapter did not declare or for a case the kit marks
// pending, and nothing else is a legitimate reason for a fence not to have been
// run.
//
// This is the same adjudication the Rust binding applies to its own report in
// `crates/morphir-mck-adapter/tests/report.rs` (finos/morphir-rust). Keeping a
// copy here lets the parent repository gate a pinned binding without building
// that binding's test suite.
import { readFileSync } from "node:fs";
import path from "node:path";

/**
 * The only reasons the driver skips a fence, taken from its own `unsupported`
 * and the pending check in `packages/mck/src/driver/run.ts`. Every message it
 * writes for a skipped record is either the exact string `pending` — the kit
 * marked the case not ready — or one of `node|version|layout|profile|path <x>
 * not in capabilities`, which is the driver declining to ask a binding for
 * something the binding said it does not do. A skip with any other message
 * means a fence went unrun for a reason nobody chose, and that is a hole in the
 * gate.
 */
const PENDING = "pending";
const UNDECLARED = "not in capabilities";

const [reportArg, allowedArg] = process.argv.slice(2);
if (reportArg === undefined || allowedArg === undefined) {
	console.error(
		"usage: bun run tools/check-mck-report.ts <report.json> <allowed-failing.json>",
	);
	process.exit(2);
}

const reportPath = path.resolve(reportArg);
const allowedPath = path.resolve(allowedArg);

interface Record_ {
	readonly caseId?: unknown;
	readonly result?: unknown;
	readonly message?: unknown;
}

function readJson(file: string, what: string): unknown {
	try {
		return JSON.parse(readFileSync(file, "utf8"));
	} catch (error) {
		console.error(`error: reading ${what} ${file}: ${String(error)}`);
		process.exit(1);
	}
}

/** The list the binding owns: the cases a kit defect is open against. */
function readAllowed(): Set<string> {
	const value = readJson(allowedPath, "the allowed-failing list") as {
		cases?: unknown;
	};
	if (!Array.isArray(value.cases)) {
		console.error(`error: ${allowedPath} has no cases array`);
		process.exit(1);
	}
	for (const entry of value.cases) {
		if (typeof entry !== "string") {
			console.error(`error: ${allowedPath} lists case ids as strings`);
			process.exit(1);
		}
	}
	return new Set(value.cases as string[]);
}

const allowed = readAllowed();
const report = readJson(reportPath, "the kit report") as {
	records?: unknown;
};
if (!Array.isArray(report.records)) {
	console.error(`error: ${reportPath} has no records array`);
	process.exit(1);
}
const records = report.records as Record_[];

const failures: string[] = [];

if (records.length === 0) {
	failures.push(
		`the kit report at ${reportPath} has no records at all, which means the driver never ran a case`,
	);
}

const counts = new Map<string, number>();
for (const record of records) {
	const result = typeof record.result === "string" ? record.result : "?";
	counts.set(result, (counts.get(result) ?? 0) + 1);
}

// An empty allow-list is only worth something if something was actually
// decoded. Without this, a run that skipped every fence — a capabilities answer
// that went wrong, say — would sail through the adjudication below.
if ((counts.get("pass") ?? 0) === 0) {
	failures.push(
		`the kit report at ${reportPath} has no passing record, so nothing was proved by this run`,
	);
}

// Every skip has to be one the binding asked for by not declaring a capability,
// or one the kit asked for by marking the case pending.
const unexplained = new Map<string, string>();
for (const record of records) {
	if (record.result !== "skipped") continue;
	const message = typeof record.message === "string" ? record.message : "";
	if (message === PENDING || message.includes(UNDECLARED)) continue;
	const caseId = typeof record.caseId === "string" ? record.caseId : "?";
	if (!unexplained.has(caseId)) unexplained.set(caseId, message);
}
if (unexplained.size > 0) {
	failures.push(
		`a fence was skipped for a reason that is neither an undeclared capability ` +
			`(${JSON.stringify(UNDECLARED)}) nor a pending case (${JSON.stringify(PENDING)}): ` +
			`${JSON.stringify(Object.fromEntries([...unexplained].sort()))}`,
	);
}

const failing = new Set<string>();
for (const record of records) {
	if (record.result !== "fail" && record.result !== "kit-error") continue;
	if (typeof record.caseId !== "string") {
		failures.push(`a ${record.result} record does not name its case`);
		continue;
	}
	failing.add(record.caseId);
}

const regressions = [...failing].filter((id) => !allowed.has(id)).sort();
const stale = [...allowed].filter((id) => !failing.has(id)).sort();
if (regressions.length > 0 || stale.length > 0) {
	failures.push(
		`the kit run does not match ${allowedPath}.\n` +
			`  failing but not listed (a regression, fix the codec): ${JSON.stringify(regressions)}\n` +
			`  listed but now passing (take it out of the list): ${JSON.stringify(stale)}`,
	);
}

const summary = ["pass", "fail", "kit-error", "skipped"]
	.map((result) => `${counts.get(result) ?? 0} ${result}`)
	.join(", ");
console.log(`${path.basename(reportPath)}: ${summary}`);

for (const failure of failures) console.log(`FAIL ${failure}`);
if (failures.length > 0) process.exit(1);
console.log(
	`the kit fails exactly the ${allowed.size} case(s) ${path.basename(allowedPath)} allows`,
);
