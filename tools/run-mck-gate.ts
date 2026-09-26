// Repository task plumbing only: the native report checker owns every verdict.
// bun run tools/run-mck-gate.ts <report> <baseline> <kit> <adapter> [adapter args...]
import { rmSync } from "node:fs";

const DEFAULT_COMMAND = ["cargo", "run", "--locked", "-p", "morphir", "--", "mck"];

export function runMckGate(
	report: string,
	baseline: string,
	kit: string,
	adapter: string,
	args: string[],
	command = DEFAULT_COMMAND,
): number {
	// A build/usage failure may leave no new report. Never adjudicate an old one.
	rmSync(report, { force: true });
	const transcript = report.endsWith(".json")
		? `${report.slice(0, -5)}.ndjson`
		: `${report}.ndjson`;
	const html = report.endsWith(".json") ? `${report.slice(0, -5)}.html` : `${report}.html`;
	rmSync(transcript, { force: true });
	rmSync(html, { force: true });
	const recordedAdapter = ["run", "tools/record-mck-transcript.ts", transcript, adapter, ...args];
	const adapterArgs = ["--adapter", "bun", ...recordedAdapter.flatMap((arg) => ["--adapter-arg", arg])];
	const run = Bun.spawnSync(
		[...command, "run", "--kit", kit, "--report", report, "--html", html, ...adapterArgs],
		{ stdio: ["inherit", "inherit", "inherit"] },
	);
	// Exit 1 includes case failures which the baseline may allow. The native
	// checker rejects missing reports and failed sessions as well as new failures.
	if (run.signalCode) return 1;
	if (run.exitCode !== 0 && run.exitCode !== 1) return run.exitCode;
	return Bun.spawnSync(
		[...command, "report", "check", report, baseline, "--kit", kit],
		{ stdio: ["inherit", "inherit", "inherit"] },
	).exitCode;
}

if (import.meta.main) {
	const argv = process.argv.slice(2);
	const [report, baseline, kit, adapter, ...args] = argv;
	if (!report || !baseline || !kit || !adapter) {
		console.error("usage: run-mck-gate.ts <report> <baseline> <kit> <adapter> [adapter args...]");
		process.exit(2);
	}
	process.exit(runMckGate(report, baseline, kit, adapter, args));
}
