// Keeps superpowers specs, plans and ledgers in beads.
//
//   bun run tools/bd-plan.ts <command> [arguments]
//   mise run beads:plan -- <command> [arguments]
//
// A plan becomes a plan epic whose description is the plan header, with one
// task bead per "### Task N" section. `render` writes the plan back to a file
// at a stable path, so the superpowers scripts (task-brief, review-package,
// task-start, task-done) keep working on a real file. A spec becomes the design
// field of its feature epic. Ledger lines become comments on the plan epic.
//
// The bead is the record. Rendered files are copies: change the bead and render
// again. See "Superpowers artifacts live in beads" in AGENTS.md.
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	statSync,
	writeFileSync,
	appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// ----- Plan text ------------------------------------------------------------

export type PlanTask = { number: number; title: string; text: string };
export type ParsedPlan = { title: string; preamble: string; tasks: PlanTask[] };

// The same task heading rule as the superpowers task-brief awk script: a line
// of hashes, then "Task", then a number, outside a ``` fence. A task's text
// runs to the next task heading or to the end of the file, exactly as
// task-brief cuts it, so a rendered plan gives the same briefs as the original.
const TASK_HEADING = /^#+[ \t]+Task[ \t]+([0-9]+)/;
const FENCE = /^```/;

export class UsageError extends Error {}

export function parsePlan(text: string): ParsedPlan {
	const lines = text.split("\n");
	let inFence = false;
	let title: string | undefined;
	const starts: { line: number; number: number; heading: string }[] = [];
	lines.forEach((line, index) => {
		if (FENCE.test(line)) {
			inFence = !inFence;
			return;
		}
		if (inFence) return;
		const task = TASK_HEADING.exec(line);
		if (task?.[1] !== undefined) {
			starts.push({ line: index, number: Number(task[1]), heading: line });
		} else if (title === undefined && starts.length === 0 && /^# /.test(line)) {
			title = line.slice(2).trim();
		}
	});
	if (title === undefined || title === "") {
		throw new UsageError("the plan has no '# ' title heading before its first task");
	}
	if (starts.length === 0) {
		throw new UsageError("the plan has no task headings (expected '### Task N: <title>')");
	}
	const seen = new Set<number>();
	for (const start of starts) {
		if (seen.has(start.number)) {
			throw new UsageError(`the plan has two headings for Task ${start.number}`);
		}
		seen.add(start.number);
	}
	// Each slice keeps its line breaks, so joining the slices gives back the
	// original text byte for byte.
	const slice = (from: number, to: number) =>
		to >= lines.length ? lines.slice(from).join("\n") : `${lines.slice(from, to).join("\n")}\n`;
	const firstTask = starts[0]?.line ?? 0;
	const tasks = starts.map((start, index) => ({
		number: start.number,
		title: taskTitle(start.number, start.heading),
		text: slice(start.line, starts[index + 1]?.line ?? lines.length),
	}));
	return { title, preamble: slice(0, firstTask), tasks };
}

function taskTitle(number: number, heading: string): string {
	const rest = heading
		.replace(TASK_HEADING, "")
		.replace(/^[ \t]*[:.\-][ \t]*/, "")
		.trim();
	return rest === "" ? `Task ${number}` : `Task ${number}: ${rest}`;
}

export function renderPlan(preamble: string, tasks: { number: number; text: string }[]): string {
	const ordered = [...tasks].sort((a, b) => a.number - b.number);
	return preamble + ordered.map((task) => task.text).join("");
}

// ----- bd -------------------------------------------------------------------

export type Bead = {
	id: string;
	title: string;
	description?: string;
	design?: string;
	status: string;
	issue_type: string;
	parent?: string | null;
	labels?: string[] | null;
	metadata?: Record<string, unknown> | null;
	dependencies?: { id: string; dependency_type?: string }[] | null;
};

type Context = { cwd: string; bd: string };

class BdError extends Error {}

function bd(context: Context, args: string[]): string {
	const result = Bun.spawnSync([context.bd, ...args], {
		cwd: context.cwd,
		env: process.env,
		stdout: "pipe",
		stderr: "pipe",
	});
	if (result.exitCode !== 0) {
		const detail = (result.stderr.toString() || result.stdout.toString()).trim();
		throw new BdError(`bd ${args.slice(0, 2).join(" ")} failed: ${detail}`);
	}
	return result.stdout.toString();
}

function bdJson<T>(context: Context, args: string[]): T {
	const out = bd(context, [...args, "--json"]);
	try {
		return JSON.parse(out) as T;
	} catch {
		throw new BdError(`bd ${args.slice(0, 2).join(" ")} did not return JSON: ${out.slice(0, 200)}`);
	}
}

function show(context: Context, id: string): Bead {
	const beads = bdJson<Bead[]>(context, ["show", id]);
	const bead = beads[0];
	if (bead === undefined) throw new BdError(`bead ${id} not found`);
	return bead;
}

function list(context: Context, filters: string[]): Bead[] {
	return bdJson<Bead[] | null>(context, ["list", "--all", "--limit", "0", ...filters]) ?? [];
}

function planTaskOf(bead: Bead): number | undefined {
	const value = bead.metadata?.plan_task;
	const number = typeof value === "number" ? value : typeof value === "string" ? Number(value) : Number.NaN;
	return Number.isInteger(number) ? number : undefined;
}

// Long texts go to bd through files, never through argv.
function withTextFile<T>(text: string, use: (file: string) => T): T {
	const dir = mkdtempSync(path.join(tmpdir(), "bd-plan-"));
	const file = path.join(dir, "text.md");
	try {
		writeFileSync(file, text);
		return use(file);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function comment(context: Context, id: string, text: string) {
	withTextFile(text, (file) => bd(context, ["comment", id, "--file", file, "--quiet"]));
}

// ----- Paths ----------------------------------------------------------------

// The nearest directory at or above `start` that holds a .git entry (a
// directory in a main checkout, a file in a linked worktree).
function repositoryRoot(start: string): string | undefined {
	let dir = path.resolve(start);
	for (;;) {
		if (existsSync(path.join(dir, ".git"))) return dir;
		const parent = path.dirname(dir);
		if (parent === dir) return undefined;
		dir = parent;
	}
}

// Repository-relative when the file is inside a checkout, absolute otherwise,
// the same convention the superpowers sdd-workspace script uses. Two
// worktrees of one repository therefore record the same path for a plan.
export function recordedPath(file: string): string {
	const absolute = path.resolve(file);
	const root = repositoryRoot(path.dirname(absolute));
	return root === undefined ? absolute : path.relative(root, absolute);
}

function defaultOut(context: Context, folder: string, id: string): string {
	const root = repositoryRoot(context.cwd) ?? context.cwd;
	return path.join(root, ".dev", folder, `${id}.md`);
}

function writeOut(file: string, text: string) {
	mkdirSync(path.dirname(file), { recursive: true });
	writeFileSync(file, text);
}

// ----- Commands -------------------------------------------------------------

type Options = { positional: string[]; flags: Map<string, string[]>; switches: Set<string> };

function parseArgs(args: string[], valued: string[], switches: string[]): Options {
	const options: Options = { positional: [], flags: new Map(), switches: new Set() };
	for (let index = 0; index < args.length; index++) {
		const arg = args[index] ?? "";
		if (arg === "--") {
			options.positional.push(...args.slice(index + 1));
			break;
		}
		const [name, inline] = arg.startsWith("--") ? arg.split(/=(.*)/s, 2) : [arg, undefined];
		if (name !== undefined && valued.includes(name)) {
			const value = inline ?? args[++index];
			if (value === undefined) throw new UsageError(`${name} needs a value`);
			options.flags.set(name, [...(options.flags.get(name) ?? []), value]);
		} else if (switches.includes(arg)) {
			options.switches.add(arg);
		} else if (arg.startsWith("--")) {
			throw new UsageError(`unknown option ${arg}`);
		} else {
			options.positional.push(arg);
		}
	}
	return options;
}

function single(options: Options, name: string): string | undefined {
	const values = options.flags.get(name) ?? [];
	if (values.length > 1) throw new UsageError(`${name} given more than once`);
	return values[0];
}

function parseLinks(values: string[]): Map<number, string> {
	const links = new Map<number, string>();
	for (const value of values) {
		const match = /^([0-9]+)=(\S+)$/.exec(value);
		if (match?.[1] === undefined || match[2] === undefined) {
			throw new UsageError(`--link expects N=<bead-id>, got '${value}'`);
		}
		const number = Number(match[1]);
		if (links.has(number)) throw new UsageError(`--link given twice for Task ${number}`);
		links.set(number, match[2]);
	}
	return links;
}

function importPlan(context: Context, args: string[]) {
	const options = parseArgs(args, ["--parent", "--spec", "--link"], []);
	const [planFile, ...extra] = options.positional;
	const parent = single(options, "--parent");
	if (planFile === undefined || extra.length > 0) throw new UsageError("import takes one plan file");
	if (parent === undefined) throw new UsageError("import needs --parent <epic-id>");
	const spec = single(options, "--spec");
	const links = parseLinks(options.flags.get("--link") ?? []);

	const absolute = path.resolve(context.cwd, planFile);
	if (!existsSync(absolute) || !statSync(absolute).isFile()) {
		throw new UsageError(`no such plan file: ${planFile}`);
	}
	const plan = parsePlan(readFileSync(absolute, "utf8"));
	const numbers = new Set(plan.tasks.map((task) => task.number));
	for (const number of links.keys()) {
		if (!numbers.has(number)) throw new UsageError(`--link names Task ${number}, which the plan does not have`);
	}
	const planPath = recordedPath(absolute);
	show(context, parent);
	if (spec !== undefined) show(context, spec);

	// Find the plan epic from an earlier import of the same file.
	const existing = list(context, ["--parent", parent, "--metadata-field", `plan_file=${planPath}`]).filter(
		(bead) => bead.issue_type === "epic",
	);
	if (existing.length > 1) {
		throw new BdError(
			`more than one plan epic under ${parent} records plan_file=${planPath}: ${existing.map((b) => b.id).join(", ")}`,
		);
	}
	const found = existing[0]?.id;
	const current = found === undefined ? new Map<number, Bead>() : currentTasks(context, found);
	// Every check on --link runs before anything is written.
	const linkedBeads = checkLinks(context, links, current, found);

	const specArgs = spec === undefined ? [] : ["--spec-id", spec];
	let epic: string;
	if (found !== undefined) {
		epic = found;
		withTextFile(plan.preamble, (file) =>
			bd(context, [
				"update",
				epic,
				"--title",
				plan.title,
				"--body-file",
				file,
				"--add-label",
				"plan",
				"--set-metadata",
				`plan_file=${planPath}`,
				...specArgs,
				"--quiet",
			]),
		);
		console.log(`updated plan epic ${epic}`);
	} else {
		epic = withTextFile(plan.preamble, (file) =>
			bd(context, [
				"create",
				"--type",
				"epic",
				"--parent",
				parent,
				"--title",
				plan.title,
				"--body-file",
				file,
				"--labels",
				"plan",
				"--metadata",
				JSON.stringify({ plan_file: planPath }),
				...specArgs,
				"--silent",
			]).trim(),
		);
		console.log(`created plan epic ${epic}`);
	}

	for (const task of plan.tasks) {
		const previous = current.get(task.number);
		current.delete(task.number);
		const bead = linkedBeads.get(task.number) ?? previous;
		if (bead === undefined) {
			const id = withTextFile(task.text, (file) =>
				bd(context, [
					"create",
					"--type",
					"task",
					"--parent",
					epic,
					"--no-inherit-labels",
					"--title",
					task.title,
					"--body-file",
					file,
					"--metadata",
					JSON.stringify({ plan_epic: epic, plan_task: task.number }),
					"--silent",
				]).trim(),
			);
			console.log(`  Task ${task.number}: created ${id}`);
			continue;
		}
		// Whether a bead is linked comes from the bead, not from this run's
		// --link options, so a later import without them keeps it linked.
		const linked = isLinked(bead, epic);
		// A linked bead keeps its title, and its old description is kept as a
		// comment the first time the plan text replaces it.
		const oldText = bead.description ?? "";
		if (previous === undefined && oldText.trim() !== "" && oldText !== task.text) {
			comment(context, bead.id, `Description before bd-plan linked this bead to ${epic} as Task ${task.number}:\n\n${oldText}`);
		}
		withTextFile(task.text, (file) =>
			bd(context, [
				"update",
				bead.id,
				...(linked ? [] : ["--title", task.title]),
				"--body-file",
				file,
				"--set-metadata",
				`plan_epic=${epic}`,
				"--set-metadata",
				`plan_task=${task.number}`,
				...(linked ? ["--set-metadata", "plan_link=true"] : []),
				"--quiet",
			]),
		);
		if (linked) bd(context, ["dep", "add", bead.id, epic, "--type", "related", "--quiet"]);
		console.log(`  Task ${task.number}: updated ${bead.id}${linked ? " (linked)" : ""}`);
	}

	// Beads for tasks the plan no longer has leave the plan. A linked bead loses
	// its plan metadata and its link to the plan epic and keeps its status. A
	// child bead cannot leave the epic's listing, because bd lists children by
	// their dotted id, so it is closed and labelled plan-removed instead.
	const today = new Date().toISOString().slice(0, 10);
	for (const [number, bead] of current) {
		const linked = isLinked(bead, epic);
		const reason = `Removed from plan ${epic} on ${today}`;
		bd(context, [
			"update",
			bead.id,
			"--unset-metadata",
			"plan_task",
			"--unset-metadata",
			"plan_epic",
			"--unset-metadata",
			"plan_link",
			...(linked ? [] : ["--add-label", "plan-removed"]),
			"--quiet",
		]);
		if (linked) {
			bd(context, ["dep", "remove", bead.id, epic, "--quiet"]);
		} else if (bead.status !== "closed") {
			bd(context, ["close", bead.id, "--reason", reason, "--quiet"]);
		}
		comment(context, bead.id, `bd-plan import: Task ${number} is no longer in ${planPath}. ${reason}.`);
		console.error(
			`warning: Task ${number} (${bead.id}) is no longer in the plan; ${linked ? "unlinked from" : "closed and labelled plan-removed in"} ${epic}`,
		);
	}
	console.log(epic);
}

// A linked bead was given to the plan with --link: it lives under another
// parent, or none. Beads linked before plan_link existed are told apart by
// their parent.
function isLinked(bead: Bead, epic: string): boolean {
	const flag = bead.metadata?.plan_link;
	return flag === true || flag === "true" || bead.parent !== epic;
}

function currentTasks(context: Context, epic: string): Map<number, Bead> {
	const current = new Map<number, Bead>();
	for (const bead of list(context, ["--metadata-field", `plan_epic=${epic}`])) {
		const number = planTaskOf(bead);
		if (number === undefined) continue;
		const other = current.get(number);
		if (other !== undefined) throw new BdError(`Task ${number} of ${epic} has two beads: ${other.id} and ${bead.id}`);
		current.set(number, bead);
	}
	return current;
}

function checkLinks(
	context: Context,
	links: Map<number, string>,
	current: Map<number, Bead>,
	epic: string | undefined,
): Map<number, Bead> {
	const byTarget = new Map<string, number>();
	for (const [number, id] of links) {
		const other = byTarget.get(id);
		if (other !== undefined) {
			throw new UsageError(`${id} is linked to Task ${other} and Task ${number}; a bead can hold one task`);
		}
		byTarget.set(id, number);
	}
	const beads = new Map<number, Bead>();
	for (const [number, id] of links) {
		const bead = show(context, id);
		const heldEpic = bead.metadata?.plan_epic;
		const heldTask = planTaskOf(bead);
		if (heldEpic !== undefined && heldTask !== undefined && (heldEpic !== epic || heldTask !== number)) {
			throw new UsageError(`${id} already holds Task ${heldTask} of ${String(heldEpic)}`);
		}
		const previous = current.get(number);
		if (previous !== undefined && previous.id !== id) {
			throw new UsageError(`Task ${number} is already ${previous.id}; --link ${number}=${id} would give it two beads`);
		}
		beads.set(number, bead);
	}
	return beads;
}

function planBeads(context: Context, epic: string): { epic: Bead; tasks: Bead[] } {
	const bead = show(context, epic);
	if (bead.metadata?.plan_file === undefined) {
		throw new UsageError(`${epic} is not a plan epic (it has no plan_file metadata); import a plan first`);
	}
	const found = list(context, ["--metadata-field", `plan_epic=${epic}`]).filter(
		(task) => planTaskOf(task) !== undefined,
	);
	// bd list may leave long fields out, so read each task in full.
	const tasks = found.length === 0 ? [] : bdJson<Bead[]>(context, ["show", ...found.map((task) => task.id)]);
	const numbers = new Map<number, string>();
	for (const task of tasks) {
		const number = planTaskOf(task) ?? 0;
		const other = numbers.get(number);
		if (other !== undefined) throw new BdError(`Task ${number} of ${epic} has two beads: ${other} and ${task.id}`);
		numbers.set(number, task.id);
	}
	return { epic: bead, tasks };
}

function render(context: Context, args: string[]) {
	const options = parseArgs(args, ["--out"], []);
	const [epic, ...extra] = options.positional;
	if (epic === undefined || extra.length > 0) throw new UsageError("render takes one plan epic id");
	const { epic: bead, tasks } = planBeads(context, epic);
	const text = renderPlan(
		bead.description ?? "",
		tasks.map((task) => ({ number: planTaskOf(task) ?? 0, text: task.description ?? "" })),
	);
	const out = path.resolve(context.cwd, single(options, "--out") ?? defaultOut(context, "beads-plans", epic));
	writeOut(out, text);
	console.log(out);
}

// The superpowers workspace for a rendered plan: the .superpowers/sdd/<dir>
// whose plan-path marker names the rendered file.
export function findWorkspace(repository: string, renderedPlans: string[]): string | undefined {
	const base = path.join(repository, ".superpowers", "sdd");
	if (!existsSync(base)) return undefined;
	const wanted = new Set(renderedPlans);
	for (const entry of readdirSync(base)) {
		const marker = path.join(base, entry, "plan-path");
		if (existsSync(marker) && wanted.has(readFileSync(marker, "utf8").trim())) return path.join(base, entry);
	}
	return undefined;
}

function ledger(context: Context, args: string[]) {
	const options = parseArgs(args, ["--workspace"], []);
	const [epic, line, ...extra] = options.positional;
	if (epic === undefined || line === undefined || extra.length > 0) {
		throw new UsageError('ledger takes a plan epic id and one line: ledger <plan-epic-id> "<line>"');
	}
	if (line.trim() === "") throw new UsageError("the ledger line is empty");
	if (line.includes("\n")) throw new UsageError("the ledger line has a line break; add one line at a time");
	const bead = show(context, epic);
	if (bead.metadata?.plan_file === undefined) throw new UsageError(`${epic} is not a plan epic`);

	const given = single(options, "--workspace");
	let workspace: string | undefined;
	if (given !== undefined) {
		workspace = path.resolve(context.cwd, given);
		if (!existsSync(workspace) || !statSync(workspace).isDirectory()) {
			throw new UsageError(`no such workspace directory: ${given}`);
		}
	} else {
		const root = repositoryRoot(context.cwd);
		const rendered = defaultOut(context, "beads-plans", epic);
		workspace =
			root === undefined ? undefined : findWorkspace(root, [path.relative(root, rendered), rendered]);
	}

	comment(context, epic, line);
	console.log(`comment added to ${epic}`);
	if (workspace === undefined) {
		console.log("no superpowers workspace found for the rendered plan; progress.md not changed");
		return;
	}
	const progress = path.join(workspace, "progress.md");
	if (!existsSync(progress)) {
		const marker = path.join(workspace, "plan-path");
		const planPath = existsSync(marker) ? readFileSync(marker, "utf8").trim() : epic;
		// The identity line the superpowers skills expect as the first line.
		writeFileSync(progress, `# SDD ledger \u2014 plan: ${planPath}\n`);
	}
	// task-done writes its completion line to progress.md itself; passing that
	// line on to the plan epic must not write it twice.
	const last = readFileSync(progress, "utf8").trimEnd().split("\n").at(-1);
	if (last === line) {
		console.log(`already the last line of ${progress}`);
		return;
	}
	appendFileSync(progress, `${line}\n`);
	console.log(`appended to ${progress}`);
}

function spec(context: Context, args: string[]) {
	const options = parseArgs(args, ["--out"], ["--render"]);
	const [epic, file, ...extra] = options.positional;
	if (epic === undefined || extra.length > 0) throw new UsageError("spec takes a feature epic id");
	if (options.switches.has("--render")) {
		if (file !== undefined) throw new UsageError("spec --render takes no spec file");
		const design = show(context, epic).design ?? "";
		if (design === "") throw new UsageError(`${epic} has no design to render`);
		const out = path.resolve(context.cwd, single(options, "--out") ?? defaultOut(context, "beads-specs", epic));
		writeOut(out, design);
		console.log(out);
		return;
	}
	if (file === undefined) throw new UsageError("spec needs a spec file, or --render");
	if (single(options, "--out") !== undefined) throw new UsageError("--out goes with --render");
	const absolute = path.resolve(context.cwd, file);
	if (!existsSync(absolute) || !statSync(absolute).isFile()) throw new UsageError(`no such spec file: ${file}`);
	const text = readFileSync(absolute, "utf8");
	if (text.trim() === "") throw new UsageError(`the spec file is empty: ${file}`);
	const old = show(context, epic).design ?? "";
	if (old.trim() !== "" && old !== text) {
		comment(context, epic, `Design before bd-plan stored ${recordedPath(absolute)}:\n\n${old}`);
		console.log(`kept the previous design of ${epic} as a comment`);
	}
	bd(context, [
		"update",
		epic,
		"--design-file",
		absolute,
		"--add-label",
		"spec",
		"--set-metadata",
		`spec_file=${recordedPath(absolute)}`,
		"--quiet",
	]);
	console.log(`stored ${file} as the design of ${epic}`);
}

// ----- Help and entry point ---------------------------------------------------

const HELP: Record<string, string> = {
	main: `bd-plan: keep superpowers specs, plans and ledgers in beads

Usage:
  bd-plan import <plan.md> --parent <epic-id> [--spec <spec-bead-id>] [--link N=<bead-id>]...
  bd-plan render <plan-epic-id> [--out <path>]
  bd-plan ledger <plan-epic-id> "<line>" [--workspace <sdd-dir>]
  bd-plan spec <feature-epic-id> <spec.md>
  bd-plan spec <feature-epic-id> --render [--out <path>]

Run it as 'bun run tools/bd-plan.ts' or 'mise run beads:plan --'.
'bd-plan <command> --help' describes one command.`,
	import: `bd-plan import <plan.md> --parent <epic-id> [--spec <spec-bead-id>] [--link N=<bead-id>]...

Store a superpowers plan as a plan epic under <epic-id>:
  - the epic: type epic, label 'plan', title from the plan's '# ' heading,
    description = the text before the first task heading,
    metadata plan_file=<path> (repository-relative), --spec-id when --spec is given;
  - one child task per '### Task N: <title>', titled 'Task N: <title>',
    description = the task's text verbatim, metadata plan_task=N and plan_epic.
A task's text runs to the next task heading or the end of the file, as the
superpowers task-brief script cuts it.

Running it again for the same plan file updates the same beads in place.
--link N=<bead-id> uses an existing bead for Task N: it gets the task text,
metadata plan_link=true and a 'related' link to the plan epic, keeps its title
and parent, and its old description is kept as a comment. It stays linked on
later imports without --link. A bead can hold one task: --link refuses a bead
named twice or one that already holds another task, before anything changes.

When a task leaves the plan, its bead leaves too: a linked bead loses its plan
metadata and its 'related' link and keeps its status; a child bead is closed
with reason 'Removed from plan <epic> on <date>' and labelled 'plan-removed'
(bd still lists it under the epic by its dotted id). Prints the plan epic id last.`,
	render: `bd-plan render <plan-epic-id> [--out <path>]

Write the plan epic's description followed by each task bead's description,
in plan_task order, to <path> (default .dev/beads-plans/<plan-epic-id>.md at
the repository root). Prints the path. Use that path as PLAN_FILE for the
superpowers scripts. Do not edit the file: change the bead and render again.`,
	ledger: `bd-plan ledger <plan-epic-id> "<line>" [--workspace <sdd-dir>]

Add <line> as a comment on the plan epic, and append it to <sdd-dir>/progress.md.
Without --workspace, the workspace is the .superpowers/sdd/<dir> whose plan-path
marker names the rendered plan (.dev/beads-plans/<plan-epic-id>.md). When there
is none, only the comment is added. A line that is already the last line of
progress.md (task-done writes its own) is not written there again.`,
	spec: `bd-plan spec <feature-epic-id> <spec.md>
bd-plan spec <feature-epic-id> --render [--out <path>]

Store a spec as the design of a feature epic, add the label 'spec' and set
metadata spec_file=<path>. A different design already on the epic is kept as
a comment first. With --render, write the design to <path> (default
.dev/beads-specs/<feature-epic-id>.md) and print the path.`,
};

const COMMANDS: Record<string, (context: Context, args: string[]) => void> = {
	import: importPlan,
	render,
	ledger,
	spec,
};

export function main(argv: string[]): number {
	const [command, ...args] = argv;
	if (command === undefined || command === "--help" || command === "-h" || command === "help") {
		console.log(HELP.main);
		return command === undefined ? 2 : 0;
	}
	const run = COMMANDS[command];
	if (run === undefined) {
		console.error(`bd-plan: unknown command '${command}'\n\n${HELP.main}`);
		return 2;
	}
	if (args.includes("--help") || args.includes("-h")) {
		console.log(HELP[command]);
		return 0;
	}
	// mise runs tasks from the repository root; resolve paths from where the
	// person typed the command.
	const context: Context = {
		cwd: process.env.MISE_ORIGINAL_CWD ?? process.cwd(),
		bd: process.env.BD_PLAN_BD ?? "bd",
	};
	try {
		run(context, args);
		return 0;
	} catch (error) {
		if (error instanceof UsageError) {
			console.error(`bd-plan ${command}: ${error.message}\n\n${HELP[command]}`);
			return 2;
		}
		if (error instanceof BdError) {
			console.error(`bd-plan ${command}: ${error.message}`);
			return 1;
		}
		throw error;
	}
}

if (import.meta.main) {
	process.exit(main(process.argv.slice(2)));
}
