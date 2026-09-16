// Runs the Morphir Compatibility Kit driver against the Rust binding's adapter.
//
//   bun run tools/run-mck-rust.ts [--suite ir|package] --kit <kit> --report <report.json>
//
// This exists only to resolve the adapter binary. `cargo build -p
// morphir-mck-adapter` writes `target/debug/mck-adapter-rust` on Linux and macOS
// and `target/debug/mck-adapter-rust.exe` on Windows, and a mise task line
// cannot spell both. Everything else is handed straight to the driver's `run`
// subcommand (or `package run`), so the task file still reads as the command it runs; `--adapter`
// is the one flag the wrapper owns and refuses to take from a caller.
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { rustMckInvocation } from "./rust-mck-command.ts";

const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

let invocation: ReturnType<typeof rustMckInvocation>;
try {
	invocation = rustMckInvocation(repositoryRoot, process.platform, process.argv.slice(2));
} catch (error) {
	console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
	process.exit(2);
}
const { adapter, command } = invocation;

if (!existsSync(adapter)) {
	console.error(
		`error: no adapter at ${path.relative(repositoryRoot, adapter)}; ` +
			"build it with `cargo build --locked -p morphir-mck-adapter --manifest-path ecosystem/morphir-rust/Cargo.toml --target-dir ecosystem/morphir-rust/target`",
	);
	process.exit(1);
}

const run = Bun.spawnSync(
	command,
	{ cwd: repositoryRoot, stdio: ["inherit", "inherit", "inherit"] },
);
process.exit(run.exitCode ?? 1);
