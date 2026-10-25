// Compares the beads database against the git-tracked export and fails when the
// two disagree.
//
//   bun run check-beads-drift.ts
//
// The database is authoritative. The readable mirror on beads-sync may be the
// legacy plain `.beads/issues.jsonl` or the 0.1.0-draft.1 compressed layout
// (gzip + manifest + index). Decompression must reproduce the export bytes
// recorded in the manifest.
//
// Every field the export owns is compared. Three are deliberately excluded:
// dependencies, because bd emits its entries in a non-deterministic order;
// the *_count fields, which bd derives from those entries; and updated_at.
//
// Pass --worktree to compare a local file instead (legacy path only), which is
// useful when diagnosing a publish that has not happened yet.
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	MIRROR_PATHS,
	parseManifest,
	verifyGzipAgainstManifest,
} from "./beads-mirror-codec.ts";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const BRANCH = "beads-sync";
const useWorktree = process.argv.includes("--worktree");

type Issue = Record<string, unknown> & { id: string };

const IGNORED_FIELDS = new Set([
	"dependencies",
	"dependency_count",
	"dependent_count",
	"comment_count",
	"updated_at",
]);

export type TrackedMirrorSource =
	| { kind: "legacy"; label: string; text: string }
	| {
			kind: "compressed";
			label: string;
			gzip: Uint8Array;
			manifestText: string;
	  };

export function loadTrackedExportText(source: TrackedMirrorSource): string {
	if (source.kind === "legacy") return source.text;
	const manifest = parseManifest(source.manifestText);
	const raw = verifyGzipAgainstManifest(source.gzip, manifest);
	return raw.toString("utf8");
}

function parse(text: string, source: string): Map<string, Issue> {
	const issues = new Map<string, Issue>();
	for (const line of text.split("\n")) {
		if (line.trim() === "") continue;
		let record: Issue;
		try {
			record = JSON.parse(line) as Issue;
		} catch (error) {
			console.error(`error: ${source} contains a malformed JSON line: ${error}`);
			process.exit(2);
		}
		if (typeof record.id !== "string") continue;
		issues.set(record.id, record);
	}
	return issues;
}

function gitShowBytes(ref: string, filePath: string): Buffer | null {
	const show = Bun.spawnSync(["git", "show", `${ref}:${filePath}`], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});
	if (show.exitCode !== 0) return null;
	return Buffer.from(show.stdout);
}

function resolveTrackedSource(): { source: TrackedMirrorSource; trackedSource: string } {
	const candidates = [BRANCH, `origin/${BRANCH}`];
	for (const ref of candidates) {
		const manifestBytes = gitShowBytes(ref, MIRROR_PATHS.manifest);
		const gzipBytes = gitShowBytes(ref, MIRROR_PATHS.gzip);
		if (manifestBytes !== null && gzipBytes !== null) {
			return {
				source: {
					kind: "compressed",
					label: `${ref}:${MIRROR_PATHS.gzip}`,
					gzip: gzipBytes,
					manifestText: manifestBytes.toString("utf8"),
				},
				trackedSource: `${ref} compressed mirror`,
			};
		}
		const legacy = gitShowBytes(ref, MIRROR_PATHS.legacyExport);
		if (legacy !== null) {
			return {
				source: {
					kind: "legacy",
					label: `${ref}:${MIRROR_PATHS.legacyExport}`,
					text: legacy.toString("utf8"),
				},
				trackedSource: `${ref}:${MIRROR_PATHS.legacyExport}`,
			};
		}
	}

	console.error(
		`error: could not read a beads mirror from ${candidates.join(" or ")}.`,
	);
	console.error(
		`Expected ${MIRROR_PATHS.manifest}+${MIRROR_PATHS.gzip} or legacy ${MIRROR_PATHS.legacyExport}.`,
	);
	console.error("Fetch the branch, or publish it with: mise run beads:publish");
	process.exit(2);
}

function describe(value: unknown): string {
	if (value === undefined) return "(absent)";
	if (typeof value === "string") {
		return value.length > 60
			? `${JSON.stringify(value.slice(0, 60))}...`
			: JSON.stringify(value);
	}
	return JSON.stringify(value);
}

async function main() {
	const exported = Bun.spawnSync(["bd", "export"], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});

	if (exported.exitCode !== 0) {
		console.error("error: could not read the beads database");
		console.error(exported.stderr.toString().trim());
		process.exit(2);
	}

	const database = parse(exported.stdout.toString(), "bd export");

	let trackedText: string;
	let trackedSource: string;

	if (useWorktree) {
		const exportPath = path.join(repositoryRoot, MIRROR_PATHS.legacyExport);
		const file = Bun.file(exportPath);
		if (!(await file.exists())) {
			console.error(`error: ${exportPath} does not exist`);
			process.exit(2);
		}
		trackedText = await file.text();
		trackedSource = `${MIRROR_PATHS.legacyExport} (working tree)`;
	} else {
		const resolved = resolveTrackedSource();
		trackedSource = resolved.trackedSource;
		try {
			trackedText = loadTrackedExportText(resolved.source);
		} catch (error) {
			console.error(
				`error: failed to load ${trackedSource}: ${error instanceof Error ? error.message : error}`,
			);
			process.exit(2);
		}
	}

	const tracked = parse(trackedText, trackedSource);

	const missingFromExport = [...database.keys()].filter((id) => !tracked.has(id));
	const missingFromDatabase = [...tracked.keys()].filter((id) => !database.has(id));

	const disagreements = [...tracked.keys()]
		.filter((id) => database.has(id))
		.flatMap((id) => {
			const a = tracked.get(id)!;
			const b = database.get(id)!;
			const names = new Set([...Object.keys(a), ...Object.keys(b)]);
			const fields: string[] = [];
			for (const name of names) {
				if (IGNORED_FIELDS.has(name)) continue;
				const left = JSON.stringify(
					Array.isArray(a[name]) ? [...(a[name] as unknown[])].sort() : a[name],
				);
				const right = JSON.stringify(
					Array.isArray(b[name]) ? [...(b[name] as unknown[])].sort() : b[name],
				);
				if (left !== right) {
					fields.push(
						`${name} export=${describe(a[name])} database=${describe(b[name])}`,
					);
				}
			}
			return fields.length > 0 ? [`${id}: ${fields.join("; ")}`] : [];
		});

	const drifted =
		missingFromExport.length + missingFromDatabase.length + disagreements.length;

	if (drifted === 0) {
		console.log(
			`beads in sync: ${database.size} issue(s) match between the database and ${trackedSource}`,
		);
		process.exit(0);
	}

	console.error(`error: the beads database and ${trackedSource} disagree.\n`);

	if (missingFromExport.length > 0) {
		console.error(
			`  ${missingFromExport.length} issue(s) in the database but not the export:`,
		);
		for (const id of missingFromExport) console.error(`    ${id}`);
		console.error("");
	}

	if (missingFromDatabase.length > 0) {
		console.error(
			`  ${missingFromDatabase.length} issue(s) in the export but not the database:`,
		);
		for (const id of missingFromDatabase) console.error(`    ${id}`);
		console.error("");
	}

	if (disagreements.length > 0) {
		console.error(`  ${disagreements.length} issue(s) disagree on a field:`);
		for (const line of disagreements) console.error(`    ${line}`);
		console.error("");
	}

	console.error("To resolve, republish the export from the database:");
	console.error("    mise run beads:publish");
	console.error("");
	console.error(
		"The database is authoritative and syncs over refs/dolt/data, so it is",
	);
	console.error(
		"almost always the side that is right. The export is a mirror: publish it",
	);
	console.error("rather than editing it.");
	console.error("");
	console.error(
		"If the export carries a change that never reached Dolt, import it first:",
	);
	console.error(
		`    git show ${BRANCH}:${MIRROR_PATHS.gzip} | gunzip | bd import -`,
	);
	console.error(
		`    # legacy: git show ${BRANCH}:${MIRROR_PATHS.legacyExport} | bd import -`,
	);

	process.exit(1);
}

if (import.meta.main) {
	await main();
}
