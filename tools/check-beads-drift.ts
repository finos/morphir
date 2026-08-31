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
// Pass --staged to compare the index rather than the working tree, which is what
// the pre-commit hook wants: a commit records what is staged, so a repaired
// working copy must not excuse a drifted staged one.
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const exportRelativePath = ".beads/issues.jsonl";
const exportPath = path.join(repositoryRoot, ".beads", "issues.jsonl");
const useStaged = process.argv.includes("--staged");

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

if (useStaged) {
	// git show :<path> prints the staged blob. A file that is tracked but not
	// staged in this commit still resolves, so this covers both cases.
	const staged = Bun.spawnSync(["git", "show", `:${exportRelativePath}`], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});
	if (staged.exitCode !== 0) {
		console.error(`error: could not read ${exportRelativePath} from the index`);
		console.error(staged.stderr.toString().trim());
		process.exit(2);
	}
	trackedText = staged.stdout.toString();
	trackedSource = `${exportRelativePath} (staged)`;
} else {
	const file = Bun.file(exportPath);
	if (!(await file.exists())) {
		console.error(`error: ${exportPath} does not exist`);
		process.exit(2);
	}
	trackedText = await file.text();
	trackedSource = exportRelativePath;
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
		`beads in sync: ${database.size} issue(s) match between the database and .beads/issues.jsonl`,
	);
	process.exit(0);
}

console.error("error: the beads database and .beads/issues.jsonl disagree.\n");

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

console.error("To resolve:");
console.error(
	"  If the database is right (the usual case, including every issue created",
);
console.error("  through bd), refresh the export and commit it:");
console.error("    bd export -o .beads/issues.jsonl");
console.error("");
console.error(
	"  If the export is right, meaning it carries a change that never reached",
);
console.error("  Dolt, import it first, then re-export:");
console.error("    bd import .beads/issues.jsonl && bd export -o .beads/issues.jsonl");
console.error("");
console.error(
	"  Compare updated_at on each side when they conflict. Never hand-edit the",
);
console.error("  export: the database is authoritative and sync travels over");
console.error("  refs/dolt/data.");

process.exit(1);
