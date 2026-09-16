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
// version 1: a top-level `formatVersions` support table and a `records` array
// of `{ caseId, irVersion, profile, role,
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

interface Record_ {
	readonly caseId?: unknown;
	readonly result?: unknown;
	readonly message?: unknown;
}

/**
 * The `Record` shape from `spec/ir/mck/report.schema.json`: the members every
 * record must have, and the closed value sets a handful of them are drawn
 * from. `path` is deliberately not in the required set below — the schema
 * makes it optional (a `kit-error` record that never resolved a path has
 * none, as in `report.example.json`) — but when it is present it still has to
 * be one of the schema's two values.
 *
 * This exists so a driver bug that emits a record with a missing or unknown
 * `result` — or any other required member missing or of the wrong type — is
 * rejected outright instead of being counted as an ignored `"?"` result and
 * silently passed through the adjudication below. The report is also
 * schema-validated by `mck:run-rust` before this checker runs; this is a
 * second, self-contained line of defense against the same contract.
 */
const RESULTS = new Set(["pass", "fail", "skipped", "kit-error"]);
const PROFILES = new Set(["json", "yaml", "tree"]);
const ROLES = new Set(["canonical", "accepted", "rejected", "file"]);
const PATHS = new Set(["current", "pinned"]);

/**
 * Returns a description of what is wrong with `record`, or `null` if it has
 * every required member of `report.schema.json`'s `Record`, each of the right
 * type, with `result` (and `profile`, `role`, and `path` when present) drawn
 * from the schema's closed value sets.
 */
export function malformedRecordReason(record: unknown, index: number): string | null {
	if (typeof record !== "object" || record === null || Array.isArray(record)) {
		return `record ${index} is not an object`;
	}
	const r = record as Record<string, unknown>;
	if (typeof r.caseId !== "string") return `record ${index} has no string caseId`;
	if (typeof r.irVersion !== "number") {
		return `record ${index} (${r.caseId}) has no number irVersion`;
	}
	if (typeof r.profile !== "string" || !PROFILES.has(r.profile)) {
		return `record ${index} (${r.caseId}) has an unrecognized profile ${JSON.stringify(r.profile)}`;
	}
	if (typeof r.role !== "string" || !ROLES.has(r.role)) {
		return `record ${index} (${r.caseId}) has an unrecognized role ${JSON.stringify(r.role)}`;
	}
	if (typeof r.fenceIndex !== "number") {
		return `record ${index} (${r.caseId}) has no number fenceIndex`;
	}
	if (r.path !== undefined && (typeof r.path !== "string" || !PATHS.has(r.path))) {
		return `record ${index} (${r.caseId}) has an unrecognized path ${JSON.stringify(r.path)}`;
	}
	if (typeof r.result !== "string" || !RESULTS.has(r.result)) {
		return `record ${index} (${r.caseId}) has an unrecognized result ${JSON.stringify(r.result)}`;
	}
	if (typeof r.durationMs !== "number") {
		return `record ${index} (${r.caseId}) has no number durationMs`;
	}
	return null;
}

/**
 * The report's top-level `formatVersions`: the support table the adapter
 * declared, in the canonical interval notation of `docs/spec/ir/format-version.md`,
 * Recognition and compatibility. The driver still decides whether the table the
 * adapter gave matches what the kit expects; what is checked here is that the
 * string is a canonical table at all, in shape and in structure.
 *
 * Canonical spelling is what makes two tables comparable as strings, so both
 * halves of it are checked: the shape of each interval, and the rule that a
 * bound which could be advanced already has been. An inclusive upper bound
 * `[a,b]` is canonical only at the patch maximum, because anywhere else it
 * spells the same set as `[a,b+1)`; an exclusive lower bound `(a,b)` is
 * canonical only at the patch maximum for the same reason.
 *
 * `unknown` is the one non-table value: the driver writes it when the run never
 * got a capabilities answer, and a report of a failed handshake still has to
 * validate.
 */
const RELEASE = "(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)";
const CANONICAL_INTERVAL = `(?:\\[${RELEASE},(?:${RELEASE})?\\)|\\(,${RELEASE}\\)|\\[${RELEASE},${RELEASE}\\]|\\(${RELEASE},${RELEASE}\\))`;
const CANONICAL_TABLE = new RegExp(`^${CANONICAL_INTERVAL}(?:,${CANONICAL_INTERVAL})*$`);
/**
 * One interval, bracket to bracket. The bound groups are release characters
 * only, so a match cannot run past the interval it started in — with `\S+?`
 * there, `[3.0.0,3.1.0),[4.0.0,4.1.0]` would match as a single interval and
 * blame 3.0.0's upper bound for 4.1.0's bracket.
 */
const INTERVAL = /([[(])([0-9.]*),([0-9.]*)([\])])/g;
/**
 * Release components are unsigned 32-bit. `RELEASE` above only forbids leading
 * zeros, so the range is checked here rather than in the grammar: without it
 * `[4.0.0,4.4294967296.0)`, a table the corpus itself calls invalid, would be
 * adjudicated clean. It also keeps the `PATCH_MAXIMUM` suffix test unambiguous —
 * a longer patch such as `14294967295` is rejected before anything asks whether
 * it ends in the component maximum.
 */
const COMPONENT_MAXIMUM = 4294967295;
const PATCH_MAXIMUM = ".4294967295";
const UNKNOWN_TABLE = "unknown";

/**
 * The release grammar starts at major 3, so an absent lower bound admits
 * releases from `3.0.0` and no bound may name an older family.
 */
const MAJOR_MINIMUM = 3;
const FIRST_RELEASE: Release = [MAJOR_MINIMUM, 0, 0];

/** A release as its three components, so bounds compare component by component. */
type Release = readonly [number, number, number];

function parseRelease(bound: string): Release {
	const [major = 0, minor = 0, patch = 0] = bound.split(".").map(Number);
	return [major, minor, patch];
}

function compareReleases(a: Release, b: Release): number {
	for (let index = 0; index < 3; index += 1) {
		const difference = (a[index] as number) - (b[index] as number);
		if (difference !== 0) return difference < 0 ? -1 : 1;
	}
	return 0;
}

/**
 * The carrying successor of the spec's emptiness and adjacency rules: patch,
 * then minor, then major when a component sits at `4294967295`. `null` is the
 * answer for `4294967295.4294967295.4294967295`, which has no next release.
 * This is deliberately not the `next()` of canonicalization, which never
 * carries.
 */
function successor(release: Release): Release | null {
	const [major, minor, patch] = release;
	if (patch < COMPONENT_MAXIMUM) return [major, minor, patch + 1];
	if (minor < COMPONENT_MAXIMUM) return [major, minor + 1, 0];
	if (major < COMPONENT_MAXIMUM) return [major + 1, 0, 0];
	return null;
}

interface Interval {
	readonly text: string;
	/** The smallest release the interval admits, or `null` when there is none. */
	readonly start: Release | null;
	/**
	 * The smallest release above the interval that it does not admit, or `null`
	 * when the interval runs to the top of the grammar.
	 */
	readonly firstExcluded: Release | null;
}

function toInterval(
	text: string,
	open: string,
	lower: string,
	upper: string,
	close: string,
): Interval {
	const start =
		lower === ""
			? FIRST_RELEASE
			: open === "["
				? parseRelease(lower)
				: successor(parseRelease(lower));
	const firstExcluded =
		upper === ""
			? null
			: close === ")"
				? parseRelease(upper)
				: successor(parseRelease(upper));
	return { text, start, firstExcluded };
}

/**
 * The structural half of canonicality, which the grammar above cannot express:
 * every bound inside the release domain, every interval non-empty, the
 * intervals ascending by lower bound, and no two of them overlapping or
 * adjacent. Without this a report could advertise `[4.1.0,4.0.0)` or
 * `[2.0.0,3.0.0)` and still be adjudicated clean.
 */
function uncanonicalIntervalsReason(value: string): string | null {
	const intervals: Interval[] = [];
	for (const [
		text = "",
		open = "",
		lower = "",
		upper = "",
		close = "",
	] of value.matchAll(INTERVAL)) {
		for (const bound of [lower, upper]) {
			if (bound === "") continue;
			if (parseRelease(bound)[0] < MAJOR_MINIMUM) {
				return `the bound ${bound} is below ${MAJOR_MINIMUM}.0.0, where the release grammar starts`;
			}
		}
		const interval = toInterval(text, open, lower, upper, close);
		if (
			interval.start === null ||
			(interval.firstExcluded !== null &&
				compareReleases(interval.start, interval.firstExcluded) >= 0)
		) {
			return `the interval ${text} contains no release`;
		}
		intervals.push(interval);
	}
	for (let index = 1; index < intervals.length; index += 1) {
		const previous = intervals[index - 1] as Interval;
		const current = intervals[index] as Interval;
		const start = current.start as Release;
		if (compareReleases(start, previous.start as Release) <= 0) {
			return `the intervals ${previous.text} and ${current.text} are not sorted by lower bound`;
		}
		if (previous.firstExcluded === null) {
			return `the intervals ${previous.text} and ${current.text} overlap`;
		}
		const order = compareReleases(start, previous.firstExcluded);
		if (order < 0) {
			return `the intervals ${previous.text} and ${current.text} overlap`;
		}
		if (order === 0) {
			return `the intervals ${previous.text} and ${current.text} are adjacent and must be merged`;
		}
	}
	return null;
}

export function malformedFormatVersionsReason(value: unknown): string | null {
	if (typeof value !== "string") return "formatVersions must be a string";
	if (value === UNKNOWN_TABLE) return null;
	if (!CANONICAL_TABLE.test(value)) {
		return `formatVersions ${JSON.stringify(value)} is not a canonical support table`;
	}
	for (const [
		,
		open = "",
		lower = "",
		upper = "",
		close = "",
	] of value.matchAll(INTERVAL)) {
		for (const bound of [lower, upper]) {
			if (bound === "") continue;
			for (const component of bound.split(".")) {
				if (Number(component) > COMPONENT_MAXIMUM) {
					return `formatVersions ${JSON.stringify(value)}: the release component ${component} is out of range`;
				}
			}
		}
		if (close === "]" && !upper.endsWith(PATCH_MAXIMUM)) {
			return `formatVersions ${JSON.stringify(value)}: an inclusive upper bound must be at the component maximum`;
		}
		if (open === "(" && lower !== "" && !lower.endsWith(PATCH_MAXIMUM)) {
			return `formatVersions ${JSON.stringify(value)}: an exclusive lower bound must be at the component maximum`;
		}
	}
	const structural = uncanonicalIntervalsReason(value);
	if (structural !== null) {
		return `formatVersions ${JSON.stringify(value)}: ${structural}`;
	}
	return null;
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
function readAllowed(allowedPath: string): Set<string> {
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

function main(): void {
	const [reportArg, allowedArg] = process.argv.slice(2);
	if (reportArg === undefined || allowedArg === undefined) {
		console.error(
			"usage: bun run tools/check-mck-report.ts <report.json> <allowed-failing.json>",
		);
		process.exit(2);
	}

	const reportPath = path.resolve(reportArg);
	const allowedPath = path.resolve(allowedArg);

	const allowed = readAllowed(allowedPath);
	const report = readJson(reportPath, "the kit report") as {
		formatVersions?: unknown;
		records?: unknown;
	};
	const tableReason = malformedFormatVersionsReason(report.formatVersions);
	if (tableReason !== null) {
		console.error(`error: ${reportPath} has a malformed report: ${tableReason}`);
		process.exit(1);
	}
	if (!Array.isArray(report.records)) {
		console.error(`error: ${reportPath} has no records array`);
		process.exit(1);
	}
	const records = report.records as Record_[];

	for (const [index, record] of records.entries()) {
		const reason = malformedRecordReason(record, index);
		if (reason !== null) {
			console.error(`error: ${reportPath} has a malformed record: ${reason}`);
			console.error(JSON.stringify(record, null, 2));
			process.exit(1);
		}
	}

	const failures: string[] = [];

	if (records.length === 0) {
		failures.push(
			`the kit report at ${reportPath} has no records at all, which means the driver never ran a case`,
		);
	}

	const counts = new Map<string, number>();
	for (const record of records) {
		const result = record.result as string;
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
}

if (import.meta.main) main();
