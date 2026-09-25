import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { parsePlan, renderPlan, UsageError } from "./bd-plan";

const TOOL = path.join(import.meta.dir, "bd-plan.ts");

const PLAN = `# Fixture Implementation Plan

> **For agentic workers:** use subagent-driven-development.

**Goal:** prove the round trip.

\`\`\`markdown
### Task 9: not a task, it is inside a fence
\`\`\`

## Global Constraints

- Keep it small.${"   "}

### Task 1: First thing

- [ ] **Step 1: Write the failing test**

\`\`\`rust
// ### Task 2: still inside a fence
fn main() {}
\`\`\`

- [ ] **Step 2: Commit**

## Task 2: Second thing, at another heading level

- [ ] Do it.

### Task 3 - Third thing

Text.

## After the plan

Notes that task-brief puts at the end of the last task.
`;

// The awk program of the superpowers task-brief script, so the test checks
// the contract even where the plugin is not installed.
const TASK_BRIEF_AWK = `
  /^\`\`\`/ { infence = !infence }
  !infence && /^#+[ \\t]+Task[ \\t]+[0-9]+/ {
    intask = ($0 ~ ("^#+[ \\t]+Task[ \\t]+" n "([^0-9]|$)"))
  }
  intask { print }
`;

function taskBrief(file: string, n: number): string {
	const result = Bun.spawnSync(["awk", "-v", `n=${n}`, TASK_BRIEF_AWK, file], { stdout: "pipe" });
	expect(result.exitCode).toBe(0);
	return result.stdout.toString();
}

describe("parsePlan", () => {
	test("splits the header and the tasks and joins back to the same text", () => {
		const plan = parsePlan(PLAN);
		expect(plan.title).toBe("Fixture Implementation Plan");
		expect(plan.tasks.map((task) => [task.number, task.title])).toEqual([
			[1, "Task 1: First thing"],
			[2, "Task 2: Second thing, at another heading level"],
			[3, "Task 3: Third thing"],
		]);
		expect(plan.preamble.endsWith("- Keep it small.   \n\n")).toBe(true);
		expect(plan.tasks[0]?.text.startsWith("### Task 1: First thing\n")).toBe(true);
		expect(plan.tasks[2]?.text.endsWith("Notes that task-brief puts at the end of the last task.\n")).toBe(true);
		expect(renderPlan(plan.preamble, [...plan.tasks].reverse())).toBe(PLAN);
	});

	test("refuses a plan without a title or without tasks", () => {
		expect(() => parsePlan("no title\n### Task 1: x\n")).toThrow(UsageError);
		expect(() => parsePlan("# Title\n\nno tasks\n")).toThrow(/no task headings/);
		expect(() => parsePlan("# T\n### Task 1: a\n### Task 1: b\n")).toThrow(/two headings for Task 1/);
	});
});

// The rest needs bd. It runs against a throwaway database in a temporary
// directory, never the project's database, and is skipped where bd is absent.
const bdPath = Bun.which("bd");

describe.skipIf(bdPath === null)("bd-plan against a throwaway beads database", () => {
	let work = "";
	let env: Record<string, string> = {};

	function run(command: string[], stdin?: string) {
		const result = Bun.spawnSync(command, {
			cwd: work,
			env,
			stdin: stdin === undefined ? "ignore" : Buffer.from(stdin),
			stdout: "pipe",
			stderr: "pipe",
		});
		return { code: result.exitCode, out: result.stdout.toString(), err: result.stderr.toString() };
	}

	function ok(command: string[]): string {
		const result = run(command);
		if (result.code !== 0) throw new Error(`${command.join(" ")} failed:\n${result.err}${result.out}`);
		return result.out;
	}

	const tool = (...args: string[]) => ok(["bun", TOOL, ...args]);
	const bdJson = (...args: string[]) => JSON.parse(ok(["bd", ...args, "--json"]));
	const lastLine = (text: string) => text.trim().split("\n").at(-1) ?? "";

	beforeAll(() => {
		work = realpathSync(mkdtempSync(path.join(tmpdir(), "bd-plan-test-")));
		// Nothing may point bd at another database.
		env = Object.fromEntries(
			Object.entries(process.env).filter(
				([key, value]) =>
					value !== undefined && !key.startsWith("BEADS_") && !key.startsWith("BD_") && key !== "MISE_ORIGINAL_CWD",
			),
		) as Record<string, string>;
		Object.assign(env, {
			GIT_AUTHOR_NAME: "bd-plan test",
			GIT_AUTHOR_EMAIL: "bd-plan@example.invalid",
			GIT_COMMITTER_NAME: "bd-plan test",
			GIT_COMMITTER_EMAIL: "bd-plan@example.invalid",
			BD_NON_INTERACTIVE: "1",
		});
		ok(["bd", "init", "--non-interactive", "--prefix", "tp", "--quiet", "--skip-agents", "--skip-hooks"]);
		expect(ok(["bd", "where"])).toContain(work.split(path.sep).at(-1) ?? "");
		writeFileSync(path.join(work, "plan.md"), PLAN);
	}, 120_000);

	afterAll(() => {
		if (work !== "") rmSync(work, { recursive: true, force: true });
	});

	test(
		"import and render round-trip a plan, and task-brief cuts the same tasks",
		() => {
			const phase = ok(["bd", "create", "--type", "epic", "--title", "Phase", "-d", "phase", "--silent"]).trim();
			const epic = lastLine(tool("import", "plan.md", "--parent", phase));

			const [bead] = bdJson("show", epic);
			expect(bead.title).toBe("Fixture Implementation Plan");
			expect(bead.issue_type).toBe("epic");
			expect(bead.labels).toContain("plan");
			expect(bead.metadata.plan_file).toBe("plan.md");
			const tasks = bdJson("list", "--parent", epic, "--all");
			expect(tasks.map((task: { title: string }) => task.title).sort()).toEqual([
				"Task 1: First thing",
				"Task 2: Second thing, at another heading level",
				"Task 3: Third thing",
			]);

			const rendered = lastLine(tool("render", epic));
			expect(rendered).toBe(path.join(work, ".dev", "beads-plans", `${epic}.md`));
			expect(readFileSync(rendered, "utf8")).toBe(PLAN);
			for (const n of [1, 2, 3]) {
				expect(taskBrief(rendered, n)).toBe(taskBrief(path.join(work, "plan.md"), n));
			}
			expect(taskBrief(rendered, 1).startsWith("### Task 1: First thing\n")).toBe(true);

			// The real script too, when the superpowers plugin is installed.
			const script = findTaskBrief();
			if (script !== undefined) {
				const out = path.join(work, "brief.md");
				ok(["bash", script, rendered, "1", out]);
				expect(readFileSync(out, "utf8")).toBe(taskBrief(path.join(work, "plan.md"), 1));
			}

			// Importing again updates in place.
			const changed = PLAN.replace("- [ ] Do it.", "- [ ] Do it twice.");
			writeFileSync(path.join(work, "plan.md"), changed);
			expect(lastLine(tool("import", "plan.md", "--parent", phase))).toBe(epic);
			expect(bdJson("list", "--parent", phase, "--all")).toHaveLength(1);
			expect(bdJson("list", "--parent", epic, "--all")).toHaveLength(3);
			expect(readFileSync(lastLine(tool("render", epic, "--out", "again.md")), "utf8")).toBe(changed);
		},
		120_000,
	);

	test(
		"--link reuses an existing bead and keeps its title and old description",
		() => {
			const phase = ok(["bd", "create", "--type", "epic", "--title", "Phase 2", "-d", "p2", "--silent"]).trim();
			const existing = ok(["bd", "create", "--title", "Existing work", "-d", "old summary", "--silent"]).trim();
			ok(["bd", "close", existing, "--reason", "done"]);
			writeFileSync(path.join(work, "linked.md"), PLAN);
			const epic = lastLine(tool("import", "linked.md", "--parent", phase, "--link", `2=${existing}`));

			const [bead] = bdJson("show", existing);
			expect(bead.title).toBe("Existing work");
			expect(bead.status).toBe("closed");
			expect(bead.metadata).toEqual({ plan_epic: epic, plan_task: 2, plan_link: true });
			expect(bead.description).toBe(parsePlan(PLAN).tasks[1]?.text);
			const comments = bdJson("comments", existing);
			expect(comments[0].text).toContain("old summary");
			expect(bdJson("list", "--parent", epic, "--all")).toHaveLength(2);
			expect(readFileSync(lastLine(tool("render", epic)), "utf8")).toBe(PLAN);

			const refused = run(["bun", TOOL, "import", "linked.md", "--parent", phase, "--link", "7=tp-x"]);
			expect(refused.code).toBe(2);
			expect(refused.err).toContain("Task 7");

			// A later import without --link still treats the bead as linked.
			tool("import", "linked.md", "--parent", phase);
			const [again] = bdJson("show", existing);
			expect(again.title).toBe("Existing work");
			expect(again.metadata).toEqual({ plan_epic: epic, plan_task: 2, plan_link: true });
			expect(bdJson("comments", existing)).toHaveLength(1);
		},
		120_000,
	);

	test(
		"one bead cannot hold two tasks, and nothing changes when a link is refused",
		() => {
			const phase = ok(["bd", "create", "--type", "epic", "--title", "Phase 4", "-d", "p4", "--silent"]).trim();
			const shared = ok(["bd", "create", "--title", "Shared", "-d", "s", "--silent"]).trim();
			writeFileSync(path.join(work, "twice.md"), PLAN);
			const twice = run(["bun", TOOL, "import", "twice.md", "--parent", phase, "--link", `1=${shared}`, "--link", `2=${shared}`]);
			expect(twice.code).toBe(2);
			expect(twice.err).toContain(`${shared} is linked to Task 1 and Task 2`);
			expect(bdJson("list", "--parent", phase, "--all")).toHaveLength(0);
			expect(bdJson("show", shared)[0].metadata ?? {}).toEqual({});

			// A bead that already holds another task of the plan.
			const epic = lastLine(tool("import", "twice.md", "--parent", phase, "--link", `2=${shared}`));
			const taken = run(["bun", TOOL, "import", "twice.md", "--parent", phase, "--link", `1=${shared}`]);
			expect(taken.code).toBe(2);
			expect(taken.err).toContain(`${shared} already holds Task 2 of ${epic}`);
			expect(bdJson("show", shared)[0].metadata).toEqual({ plan_epic: epic, plan_task: 2, plan_link: true });
		},
		120_000,
	);

	test(
		"tasks that leave the plan are detached from it",
		() => {
			const phase = ok(["bd", "create", "--type", "epic", "--title", "Phase 5", "-d", "p5", "--silent"]).trim();
			const linked = ok(["bd", "create", "--title", "Linked work", "-d", "l", "--silent"]).trim();
			writeFileSync(path.join(work, "shrink.md"), PLAN);
			const epic = lastLine(tool("import", "shrink.md", "--parent", phase, "--link", `2=${linked}`));
			const child = bdJson("list", "--metadata-field", `plan_epic=${epic}`, "--metadata-field", "plan_task=3", "--all")[0].id;

			const plan = parsePlan(PLAN);
			const smaller = plan.preamble + (plan.tasks[0]?.text ?? "");
			writeFileSync(path.join(work, "shrink.md"), smaller);
			tool("import", "shrink.md", "--parent", phase);

			const [left] = bdJson("show", linked);
			expect(left.status).toBe("open");
			expect(left.metadata ?? {}).toEqual({});
			expect(left.dependencies ?? []).toEqual([]);

			const [removed] = bdJson("show", child);
			expect(removed.status).toBe("closed");
			expect(removed.close_reason).toMatch(new RegExp(`^Removed from plan ${epic.replace(".", "\\.")} on \\d{4}-\\d{2}-\\d{2}$`));
			expect(removed.labels).toContain("plan-removed");
			expect(removed.metadata ?? {}).toEqual({});
			expect(bdJson("list", "--parent", epic, "--all", "--exclude-label", "plan-removed")).toHaveLength(1);
			expect(readFileSync(lastLine(tool("render", epic)), "utf8")).toBe(smaller);
		},
		120_000,
	);

	test(
		"ledger lines become comments and reach the workspace of the rendered plan",
		() => {
			const phase = ok(["bd", "create", "--type", "epic", "--title", "Phase 3", "-d", "p3", "--silent"]).trim();
			writeFileSync(path.join(work, "ledgered.md"), PLAN);
			const epic = lastLine(tool("import", "ledgered.md", "--parent", phase));
			tool("render", epic);
			// What the superpowers sdd-workspace script leaves for the rendered plan.
			const workspace = path.join(work, ".superpowers", "sdd", epic);
			mkdirSync(workspace, { recursive: true });
			writeFileSync(path.join(workspace, "plan-path"), `.dev/beads-plans/${epic}.md\n`);

			tool("ledger", epic, "Task 1: complete (commits abc1234..def5678, tests: bun test -> 3 pass)");
			tool("ledger", epic, "- Ruling: keep the fence rule");
			// As after task-done: the line is already in progress.md.
			appendFileSync(path.join(workspace, "progress.md"), "Task 2: complete\n");
			tool("ledger", epic, "Task 2: complete");
			const progress = readFileSync(path.join(workspace, "progress.md"), "utf8").split("\n");
			expect(progress[0]).toBe(`# SDD ledger \u2014 plan: .dev/beads-plans/${epic}.md`);
			expect(progress.slice(1)).toEqual([
				"Task 1: complete (commits abc1234..def5678, tests: bun test -> 3 pass)",
				"- Ruling: keep the fence rule",
				"Task 2: complete",
				"",
			]);
			const comments = bdJson("comments", epic).map((entry: { text: string }) => entry.text);
			expect(comments).toEqual([
				"Task 1: complete (commits abc1234..def5678, tests: bun test -> 3 pass)",
				"- Ruling: keep the fence rule",
				"Task 2: complete",
			]);
		},
		120_000,
	);

	test(
		"spec stores a design and renders it back",
		() => {
			const feature = ok(["bd", "create", "--type", "epic", "--title", "Feature", "-d", "f", "--silent"]).trim();
			const text = "# Design\n\nThe spec.\t \n\n```\n### Task 1: not a task\n```\n";
			writeFileSync(path.join(work, "spec.md"), text);
			tool("spec", feature, "spec.md");
			const [bead] = bdJson("show", feature);
			expect(bead.design).toBe(text);
			expect(bead.labels).toContain("spec");
			expect(bead.metadata.spec_file).toBe("spec.md");
			const out = lastLine(tool("spec", feature, "--render"));
			expect(out).toBe(path.join(work, ".dev", "beads-specs", `${feature}.md`));
			expect(readFileSync(out, "utf8")).toBe(text);

			// A second, different spec keeps the first one as a comment.
			writeFileSync(path.join(work, "spec.md"), "# Design v2\n");
			tool("spec", feature, "spec.md");
			expect(bdJson("comments", feature)[0].text).toContain("The spec.");
		},
		120_000,
	);

	test("help and errors", () => {
		expect(run(["bun", TOOL, "--help"]).out).toContain("bd-plan import");
		for (const command of ["import", "render", "ledger", "spec"]) {
			const help = run(["bun", TOOL, command, "--help"]);
			expect(help.code).toBe(0);
			expect(help.out).toContain(`bd-plan ${command}`);
		}
		expect(run(["bun", TOOL, "nope"]).code).toBe(2);
		expect(run(["bun", TOOL, "import", "missing.md", "--parent", "tp-x"]).err).toContain("no such plan file");
		expect(run(["bun", TOOL, "render", "tp-missing"]).code).toBe(1);
	});
});

function findTaskBrief(): string | undefined {
	const cache = path.join(homedir(), ".claude", "plugins", "cache");
	if (!existsSync(cache)) return undefined;
	const glob = new Bun.Glob("**/superpowers/*/skills/subagent-driven-development/scripts/task-brief");
	for (const match of glob.scanSync({ cwd: cache, onlyFiles: true })) return path.join(cache, match);
	return undefined;
}
