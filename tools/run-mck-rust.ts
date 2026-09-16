// Runs the Morphir Compatibility Kit driver against the Rust binding's adapter.
//
//   bun run tools/run-mck-rust.ts --kit <kit> --report <report.json>
//
// This exists only to resolve the adapter binary. `cargo build -p
// morphir-mck-adapter` writes `target/debug/mck-adapter-rust` on Linux and macOS
// and `target/debug/mck-adapter-rust.exe` on Windows, and a mise task line
// cannot spell both. Everything else is handed straight to the driver's `run`
// subcommand, so the task file still reads as the command it runs.
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

const driver = path.join(
	repositoryRoot,
	"ecosystem",
	"morphir-typescript",
	"packages",
	"mck",
	"src",
	"cli.ts",
);
const adapterDirectory = path.join(
	repositoryRoot,
	"ecosystem",
	"morphir-rust",
	"target",
	"debug",
);
const adapter = path.join(
	adapterDirectory,
	process.platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust",
);

if (!existsSync(adapter)) {
	console.error(
		`error: no adapter at ${path.relative(repositoryRoot, adapter)}; ` +
			"build it with `cargo build -p morphir-mck-adapter --manifest-path ecosystem/morphir-rust/Cargo.toml`",
	);
	process.exit(1);
}

const run = Bun.spawnSync(
	["bun", driver, "run", "--adapter", adapter, ...process.argv.slice(2)],
	{ cwd: repositoryRoot, stdio: ["inherit", "inherit", "inherit"] },
);
process.exit(run.exitCode ?? 1);
