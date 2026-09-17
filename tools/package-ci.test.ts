import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const tasks = Bun.TOML.parse(readFileSync(new URL("../.config/mise/config.toml", import.meta.url), "utf8")) as {
	tasks: Record<string, { run: string[] }>;
};
type Job = { needs?: string[]; if?: string; steps: { run?: string; uses?: string; if?: string; with?: Record<string, string> }[] };
const workflow = Bun.YAML.parse(readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8")) as { jobs: Record<string, Job> };

test("Rust package task builds a locked adapter and delegates verdicts to shared MCK", () => {
	const runs = tasks.tasks["package:check:rust"]?.run ?? [];
	expect(runs.some((run) => run.includes("cargo build --locked") && run.includes("--target-dir ecosystem/morphir-rust/target"))).toBe(true);
	expect(runs).toContain("bun run tools/run-mck-rust.ts --suite package --kit spec/package/mck --report .dev/out/mck/package-rust.json");
	expect(runs.some((run) => run.includes("check-mck-report"))).toBe(false);
});

test("resolution tasks select draft.2 for both transports and implementations", () => {
	expect(tasks.tasks["package:resolution-check"]?.run).toEqual([
		"bun install --frozen-lockfile --cwd ecosystem/morphir-typescript",
		"bun ecosystem/morphir-typescript/packages/mck/src/cli.ts package run --contract 0.1.0-draft.2 --kit spec/package/mck --report .dev/out/mck/package-resolution-typescript.json",
		"bun ecosystem/morphir-typescript/packages/mck/src/cli.ts package run --contract 0.1.0-draft.2 --kit spec/package/mck --adapter bun --adapter-arg ecosystem/morphir-typescript/packages/mck/src/adapter.ts --adapter-arg --suite --adapter-arg package --adapter-arg --contract --adapter-arg 0.1.0-draft.2 --report .dev/out/mck/package-resolution-typescript-adapter.json",
	]);
	expect(tasks.tasks["package:resolution-check:rust"]?.run).toEqual([
		"bun install --frozen-lockfile --cwd ecosystem/morphir-typescript",
		"cargo build --locked -p morphir-mck-adapter --manifest-path ecosystem/morphir-rust/Cargo.toml --target-dir ecosystem/morphir-rust/target",
		"bun run tools/run-mck-rust.ts --suite package --contract 0.1.0-draft.2 --kit spec/package/mck --report .dev/out/mck/package-resolution-rust.json",
	]);
});

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

test("package CI covers each input and always uploads its report", () => {
	const filters = workflow.jobs.changes?.steps.find((step) => step.with?.filters)?.with?.filters ?? "";
	const paths = (Bun.YAML.parse(filters) as Record<string, string[]>)["package-mck"] ?? [];
	for (const input of ["spec/package/**", "ecosystem/morphir-rust", "ecosystem/morphir-typescript", "tools/run-mck-rust.ts", "tools/rust-mck-command*", "tools/package-ci.test.ts", ".config/mise/config.toml", ".github/workflows/ci.yml"]) {
		expect(paths).toContain(input);
	}
	const job = workflow.jobs["package-mck"];
	expect(job?.if).toContain("needs.changes.outputs.package-mck == 'true'");
	expect(job?.steps.some((step) => step.run === "mise run package:check:rust")).toBe(true);
	expect(job?.steps.find((step) => step.run === "mise run package:check:rust")?.if)
		.toBe("${{ !cancelled() && steps.integration.outcome == 'success' }}");
	expect(job?.steps.some((step) => step.run === "mise run package:check")).toBe(true);
	for (const task of ["package:resolution-check", "package:resolution-check:rust"]) {
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
	expect(workflow.jobs["package-mck"]?.steps.some((step) => step.run?.includes("bun test tools/rust-mck-command.test.ts tools/package-ci.test.ts"))).toBe(true);
});
