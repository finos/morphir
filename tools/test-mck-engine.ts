// Build the maintained MEP peer once, then run the ordinary MCK engine group.
// Usage: bun run tools/test-mck-engine.ts [--lib] [test-name-filter]
import { spawnSync } from "node:child_process";
import { statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { builtExecutable } from "./cargo-artifacts.ts";

type RunnerOptions = {
	cwd: string;
	env: Record<string, string | undefined>;
	/** Trusted subprocess fixture seam. The CLI always uses literal cargo. */
	cargo?: readonly [string, ...string[]];
};

function testSelection(args: readonly string[]): string[] {
	let library = false;
	let filter: string | undefined;
	for (const arg of args) {
		if (arg === "--lib" && !library) library = true;
		else if (arg.length > 0 && !arg.startsWith("-") && filter === undefined) filter = arg;
		else throw new Error("usage: bun run tools/test-mck-engine.ts [--lib] [test-name-filter]");
	}
	return [...(library ? ["--lib"] : []), ...(filter === undefined ? [] : [filter])];
}

export function runMckEngineTests(args: readonly string[], options: RunnerOptions): number {
	const selection = testSelection(args);
	const [command, ...prefix] = options.cargo ?? ["cargo"];
	const env = Object.fromEntries(
		Object.entries(options.env).filter(([name]) => name.toUpperCase() !== "MORPHIR_MCK_REPORT_PEER_BIN"),
	);
	const build = spawnSync(command, [
		...prefix, "test", "--locked", "-p", "morphir-mck", "--test", "mep_transport",
		"--no-run", "--message-format=json-render-diagnostics",
	], {
		cwd: options.cwd,
		env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "inherit"],
		windowsHide: true,
		// Cargo's complete trusted artifact stream can exceed Node's default 1 MiB.
		maxBuffer: Infinity,
	});
	if (build.error) throw build.error;
	if (build.status !== 0) {
		process.stdout.write(build.stdout ?? "");
		return build.status ?? 1;
	}
	const peer = builtExecutable(build.stdout, { name: "mep_transport", kind: "test" });
	if (!statSync(peer).isFile()) throw new Error("cargo's reported MEP peer is not a file");
	const tests = spawnSync(command, [...prefix, "test", "--locked", "-p", "morphir-mck", ...selection], {
		cwd: options.cwd,
		env: { ...env, MORPHIR_MCK_REPORT_PEER_BIN: peer },
		stdio: "inherit",
		windowsHide: true,
	});
	if (tests.error) throw tests.error;
	return tests.status ?? 1;
}

if (import.meta.main) {
	try {
		process.exitCode = runMckEngineTests(process.argv.slice(2), {
			cwd: path.dirname(path.dirname(fileURLToPath(import.meta.url))),
			env: process.env,
		});
	} catch (error) {
		console.error(error instanceof Error ? error.message : error);
		process.exitCode = 1;
	}
}
