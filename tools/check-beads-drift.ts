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
// Only fields the export owns are compared. The dependencies array is skipped
// because bd emits its entries in a non-deterministic order, which produces diff
// churn but never means the two sides disagree.
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const exportPath = path.join(repositoryRoot, ".beads", "issues.jsonl");

type Issue = {
	id: string;
	title?: string;
	status?: string;
	priority?: number;
};

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

const file = Bun.file(exportPath);
if (!(await file.exists())) {
	console.error(`error: ${exportPath} does not exist`);
	process.exit(2);
}
const tracked = parse(await file.text(), exportPath);

const missingFromExport = [...database.keys()].filter((id) => !tracked.has(id));
const missingFromDatabase = [...tracked.keys()].filter((id) => !database.has(id));
const disagreements = [...tracked.keys()]
	.filter((id) => database.has(id))
	.flatMap((id) => {
		const a = tracked.get(id)!;
		const b = database.get(id)!;
		const fields: string[] = [];
		if (a.status !== b.status) {
			fields.push(`status export=${a.status} database=${b.status}`);
		}
		if (a.priority !== b.priority) {
			fields.push(`priority export=${a.priority} database=${b.priority}`);
		}
		return fields.length > 0 ? [`${id}: ${fields.join(", ")}`] : [];
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
