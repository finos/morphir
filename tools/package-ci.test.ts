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
