// Compares the beads database against the git-tracked export and fails when the
// two disagree.
//
//   bun run check-beads-drift.ts
//
// The database is authoritative and .beads/issues.jsonl is a passive export, so
// the two drift apart whenever issues are committed to Dolt without a re-export,
// or the export is edited and committed to git without a matching dolt push.
// Both happened before this check existed (morphir-5uau): 17 issues lived only
// in the database, one lived only in the export, and five disagreed on status.
//
// Every field the export owns is compared. Three are deliberately excluded:
// dependencies, because bd emits its entries in a non-deterministic order, which
// produces diff churn without meaning the two sides disagree; the *_count fields,
// which bd derives from those entries; and updated_at, which moves for reasons
// that do not change the issue's content.
//
// The export is compared as published on the beads-sync branch, which is the
// only copy git tracks. Pass --worktree to compare the local file instead, which
// is useful when diagnosing a publish that has not happened yet.
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const BRANCH = "beads-sync";
const exportRelativePath = ".beads/issues.jsonl";
const exportPath = path.join(repositoryRoot, ".beads", "issues.jsonl");
const useWorktree = process.argv.includes("--worktree");

type Issue = Record<string, unknown> & { id: string };

// Compared field by field. Anything bd derives or reorders is left out.
const IGNORED_FIELDS = new Set([
	"dependencies",
	"dependency_count",
	"dependent_count",
	"comment_count",
	"updated_at",
]);

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
		// Memory records share the file but carry no issue id.
		if (typeof record.id !== "string") continue;
		issues.set(record.id, record);
	}
	return issues;
}

// bd export writes to stdout when no -o is given.
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
	const file = Bun.file(exportPath);
	if (!(await file.exists())) {
		console.error(`error: ${exportPath} does not exist`);
		process.exit(2);
	}
	trackedText = await file.text();
	trackedSource = `${exportRelativePath} (working tree)`;
} else {
	// Prefer the local branch; fall back to the remote so the check still works
	// in a fresh clone that has not fetched the branch into a local ref.
	const candidates = [BRANCH, `origin/${BRANCH}`];
	let found: { ref: string; text: string } | null = null;
	for (const ref of candidates) {
		const show = Bun.spawnSync(["git", "show", `${ref}:${exportRelativePath}`], {
			cwd: repositoryRoot,
			stderr: "pipe",
		});
		if (show.exitCode === 0) {
			found = { ref, text: show.stdout.toString() };
			break;
		}
	}
	if (found === null) {
		console.error(
			`error: could not read ${exportRelativePath} from ${candidates.join(" or ")}.`,
		);
		console.error("Fetch the branch, or publish it with: mise run beads:publish");
		process.exit(2);
	}
	trackedText = found.text;
	trackedSource = `${found.ref}:${exportRelativePath}`;
}

const tracked = parse(trackedText, trackedSource);

const missingFromExport = [...database.keys()].filter((id) => !tracked.has(id));
const missingFromDatabase = [...tracked.keys()].filter((id) => !database.has(id));
function describe(value: unknown): string {
	if (value === undefined) return "(absent)";
	if (typeof value === "string") {
		return value.length > 60 ? `${JSON.stringify(value.slice(0, 60))}...` : JSON.stringify(value);
	}
	return JSON.stringify(value);
}

const disagreements = [...tracked.keys()]
	.filter((id) => database.has(id))
	.flatMap((id) => {
		const a = tracked.get(id)!;
		const b = database.get(id)!;
		const names = new Set([...Object.keys(a), ...Object.keys(b)]);
		const fields: string[] = [];
		for (const name of names) {
			if (IGNORED_FIELDS.has(name)) continue;
			// Order within labels is not meaningful either.
			const left = JSON.stringify(
				Array.isArray(a[name]) ? [...(a[name] as unknown[])].sort() : a[name],
			);
			const right = JSON.stringify(
				Array.isArray(b[name]) ? [...(b[name] as unknown[])].sort() : b[name],
			);
			if (left !== right) {
				fields.push(`${name} export=${describe(a[name])} database=${describe(b[name])}`);
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
console.error(`    git show ${BRANCH}:${exportRelativePath} | bd import -`);

process.exit(1);
