import { expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";

const tasks = Bun.TOML.parse(readFileSync(new URL("../.config/mise/config.toml", import.meta.url), "utf8")) as {
	tasks: Record<string, { run: string[] }>;
};
type Job = {
	needs?: string[];
	if?: string;
	"continue-on-error"?: boolean | string;
	steps: { run?: string; uses?: string; if?: string; "continue-on-error"?: boolean | string; with?: Record<string, string> }[];
};
const workflow = Bun.YAML.parse(readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8")) as { jobs: Record<string, Job> };

for (const [task, binding, contract] of [
	["package:check", "typescript", "0.1.0-draft.1"],
	["package:check:rust", "rust", "0.1.0-draft.1"],
	["package:resolution-check", "typescript", "0.1.0-draft.2"],
	["package:resolution-check:rust", "rust", "0.1.0-draft.2"],
]) {
	test(`${task} delegates to the native runner with an explicit adapter`, () => {
		const runs = tasks.tasks[task!]!.run;
		expect(runs.at(-1)).toBe(`bun run tools/run-package-mck.ts ${binding} ${contract}`);
		expect(runs.some(run => run.includes("src/cli.ts") || run.includes("run-mck-rust"))).toBe(false);
		if (binding === "rust") {
			expect(runs.some(run => run.includes("cargo build --locked") && run.includes("--target-dir ecosystem/morphir-rust/target"))).toBe(true);
			expect(runs.some(run => run.includes("bun install"))).toBe(false);
		}
	});
}

test("package schema validation covers every indexed resolution fixture", () => {
	const index = JSON.parse(readFileSync(new URL("../spec/package/mck/resolution-cases.json", import.meta.url), "utf8")) as {
		fixtures: readonly string[];
	};
	const schemaRuns = tasks.tasks["package:schema-check"]?.run ?? [];
	const resolutionValidation = schemaRuns.find((run) => run.includes("resolution-case.schema.json") && run.includes("jsonschema validate")) ?? "";
	for (const fixture of index.fixtures) {
		expect(resolutionValidation).toContain(`spec/package/mck/${fixture}`);
	}
});

test("assurance task executes parent vectors through shared MCK support", () => {
	expect(tasks.tasks["package:assurance-check"]?.run).toEqual([
		"bun install --frozen-lockfile --cwd ecosystem/morphir-typescript",
		"bun ecosystem/morphir-typescript/packages/mck/test/support/local-registry-assurance-parent-integration.ts --source .",
	]);
});

test("publisher task checks fixed parent statements through shared MCK support", () => {
	expect(tasks.tasks["package:publisher-check"]?.run).toEqual([
		"bun install --frozen-lockfile --cwd ecosystem/morphir-typescript",
		"bun ecosystem/morphir-typescript/packages/mck/test/support/local-registry-publisher-parent-integration.ts --source .",
	]);
});

test("package CI requires one publisher check after assurance without suppressing failure", () => {
	const job = workflow.jobs["package-mck"];
	const publisherSteps = job?.steps.filter((step) => step.run === "mise run package:publisher-check") ?? [];
	expect(publisherSteps).toHaveLength(1);
	expect(publisherSteps[0]?.if).toBe("${{ !cancelled() && steps.integration.outcome == 'success' }}");
	expect(publisherSteps[0]?.["continue-on-error"]).toBeUndefined();
	expect(job?.["continue-on-error"]).toBeUndefined();
	const assuranceIndex = job?.steps.findIndex((step) => step.run === "mise run package:assurance-check") ?? -1;
	const publisherIndex = job?.steps.findIndex((step) => step.run === "mise run package:publisher-check") ?? -1;
	expect(assuranceIndex).toBeGreaterThanOrEqual(0);
	expect(publisherIndex).toBeGreaterThan(assuranceIndex);
});

for (const schema of [
	"package-restore-assurance-protocol.schema.json", "package-restore-assurance-report.schema.json",
	"package-protocol.schema.json", "package-report.schema.json",
	"package-resolution-protocol.schema.json", "package-resolution-report.schema.json",
]) {
	test(`shared MCK ${schema} mirrors the canonical parent schema`, () => {
		const canonical = new URL(`../spec/package/schemas/${schema}`, import.meta.url);
		expect(existsSync(canonical)).toBe(true);
		const mirror = new URL(`../ecosystem/morphir-typescript/packages/mck/${schema}`, import.meta.url);
		expect(JSON.parse(readFileSync(mirror, "utf8"))).toEqual(JSON.parse(readFileSync(canonical, "utf8")));
	});

	test(`package schema check validates canonical ${schema}`, () => {
		const runs = tasks.tasks["package:schema-check"]?.run ?? [];
		expect(runs.some((run) => run.startsWith("jsonschema metaschema ") && run.split(" ").includes(`spec/package/schemas/${schema}`))).toBe(true);
	});
}

test("package CI covers each input and always uploads its report", () => {
	const filters = workflow.jobs.changes?.steps.find((step) => step.with?.filters)?.with?.filters ?? "";
	const paths = (Bun.YAML.parse(filters) as Record<string, string[]>)["package-mck"] ?? [];
	for (const input of ["spec/package/**", "ecosystem/morphir-rust", "ecosystem/morphir-typescript", "tools/run-package-mck.ts", "tools/package-mck-command*", "tools/package-ci.test.ts", ".config/mise/config.toml", ".github/workflows/ci.yml"]) {
		expect(paths).toContain(input);
	}
	const job = workflow.jobs["package-mck"];
	expect(job?.if).toContain("needs.changes.outputs.package-mck == 'true'");
	expect(job?.steps.some((step) => step.run === "mise run package:check:rust")).toBe(true);
	expect(job?.steps.find((step) => step.run === "mise run package:check:rust")?.if)
		.toBe("${{ !cancelled() && steps.integration.outcome == 'success' }}");
	expect(job?.steps.some((step) => step.run === "mise run package:check")).toBe(true);
	for (const task of ["package:resolution-check", "package:resolution-check:rust", "package:assurance-check"]) {
		expect(job?.steps.some((step) => step.run === `mise run ${task}`)).toBe(true);
		expect(job?.steps.find((step) => step.run === `mise run ${task}`)?.if)
			.toBe("${{ !cancelled() && steps.integration.outcome == 'success' }}");
	}
	const upload = job?.steps.find((step) => step.uses?.startsWith("actions/upload-artifact@"));
	expect(upload?.if).toBe("always()");
	expect(upload?.with?.path).toBe(".dev/out/mck/package-*.json");
});

test("aggregate gate requires successful package CI when selected", () => {
	expect(workflow.jobs.check?.needs).toContain("package-mck");
	const check = workflow.jobs.check?.steps.map((step) => step.run ?? "").join("\n") ?? "";
	expect(check).toContain('needs.changes.outputs.package-mck');
	expect(check).toContain('needs.package-mck.result');
	expect(workflow.jobs["package-mck"]?.steps.some((step) => step.run?.includes("bun test tools/package-mck-command.test.ts tools/record-mck-transcript.test.ts tools/package-ci.test.ts"))).toBe(true);
});

test("native package changes select authoritative gates after legacy cutover", () => {
	const filters = workflow.jobs.changes?.steps.find(step => step.with?.filters)?.with?.filters ?? "";
	const paths = (Bun.YAML.parse(filters) as Record<string, string[]>)["package-mck"] ?? [];
	for (const input of ["crates/morphir-mck/**", "crates/morphir/**", "Cargo.toml", "Cargo.lock", "spec/mck/baseline/package-cases.json", "tools/package-mck-command*", "tools/run-package-mck.ts"]) expect(paths).toContain(input);
	expect(tasks.tasks["package:native-parity"]).toBeUndefined();
	const steps = workflow.jobs["package-mck"]?.steps ?? [];
	expect(steps.some(step => step.run?.includes("package:native-parity"))).toBe(false);
	expect(steps.some(step => step.uses === "./.github/actions/setup-rust-ci")).toBe(true);
});
