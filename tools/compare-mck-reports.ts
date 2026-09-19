// Compares two Morphir Compatibility Kit reports of the same run.
//
//   bun run tools/compare-mck-reports.ts <old.json> <new.json>
//
// Parity between the first driver and the Rust runner is report equality with
// three exclusions: the wall clock, timing, and the driver's own version
// (spec/mck/migration.md, "Parity method"). Nothing else is forgiven: record
// order, kit errors, skip reasons and messages all have to match, and a
// shorter report is a difference rather than a prefix that happens to agree.
//
// It is development and CI tooling: the shipped CLI never depends on it.
import { readFileSync } from "node:fs";

/** What a run is allowed to differ in, because it identifies the run, not its result. */
export const PERMITTED = ["startedAt", "durationMs", "driverVersion"] as const;

type Report = Record<string, unknown> & { records?: unknown[] };

const show = (value: unknown) => JSON.stringify(value) ?? "undefined";

/** Every way `fresh` differs from `old`, in report order, or an empty list. */
export function compareReports(old: Report, fresh: Report): string[] {
	const differences: string[] = [];
	const members = [...new Set([...Object.keys(old), ...Object.keys(fresh)])]
		.filter((member) => member !== "records" && !PERMITTED.includes(member as typeof PERMITTED[number]));
	for (const member of members) {
		if (show(old[member]) !== show(fresh[member])) {
			differences.push(`${member}: ${show(old[member])} vs ${show(fresh[member])}`);
		}
	}

	const [oldRecords, freshRecords] = [old.records ?? [], fresh.records ?? []];
	if (oldRecords.length !== freshRecords.length) {
		differences.push(`record count: ${oldRecords.length} vs ${freshRecords.length}`);
	}
	for (let i = 0; i < Math.min(oldRecords.length, freshRecords.length); i++) {
		const [a, b] = [oldRecords[i] as Record<string, unknown>, freshRecords[i] as Record<string, unknown>];
		const fields = [...new Set([...Object.keys(a), ...Object.keys(b)])]
			.filter((field) => field !== "durationMs");
		for (const field of fields) {
			if (show(a[field]) !== show(b[field])) {
				differences.push(
					`record ${i} (${String(a.caseId ?? b.caseId)} fence ${String(a.fenceIndex ?? b.fenceIndex)}) ` +
						`${field}: ${show(a[field])} vs ${show(b[field])}`,
				);
			}
		}
	}
	return differences;
}

if (import.meta.main) {
	const [before, after] = process.argv.slice(2);
	if (before === undefined || after === undefined) {
		console.error("usage: compare-mck-reports <old.json> <new.json>");
		process.exit(2);
	}
	const read = (file: string) =>
		JSON.parse(readFileSync(file, "utf8").replace(/^﻿/, "")) as Report;
	const differences = compareReports(read(before), read(after));
	if (differences.length > 0) {
		console.error(`error: ${differences.length} difference(s) between ${before} and ${after}:`);
		for (const difference of differences.slice(0, 50)) console.error(`  ${difference}`);
		if (differences.length > 50) console.error(`  ... and ${differences.length - 50} more`);
		process.exit(1);
	}
	console.log(`${before} and ${after} agree apart from ${PERMITTED.join(", ")}`);
}
