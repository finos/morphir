// Runs the Morphir Compatibility Kit driver against the Rust binding's adapter.
//
//   bun run tools/run-mck-rust.ts --kit <kit> --report <report.json>
//
// This exists only to resolve the adapter binary. `cargo build -p
// morphir-mck-adapter` writes `target/debug/mck-adapter-rust` on Linux and macOS
// and `target/debug/mck-adapter-rust.exe` on Windows, and a mise task line
// cannot spell both. Everything else is handed straight to the driver's `run`
// subcommand, so the task file still reads as the command it runs; `--adapter`
// is the one flag the wrapper owns and refuses to take from a caller.
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
			"build it with `cargo build --locked -p morphir-mck-adapter --manifest-path ecosystem/morphir-rust/Cargo.toml`",
	);
	process.exit(1);
}

// Choosing the adapter is the one thing this wrapper is for, so a caller who
// also passes `--adapter` is asking for something it cannot honour: the driver
// would see the flag twice. Say so rather than pass a contradiction along.
const forwarded = process.argv.slice(2);
if (forwarded.includes("--adapter") || forwarded.some((argument) => argument.startsWith("--adapter="))) {
	console.error(
		"error: this wrapper supplies --adapter (it resolves the binary's name per platform); " +
			"run the driver directly to point it at a different adapter",
	);
	process.exit(2);
}

const run = Bun.spawnSync(
	["bun", driver, "run", "--adapter", adapter, ...forwarded],
	{ cwd: repositoryRoot, stdio: ["inherit", "inherit", "inherit"] },
);
process.exit(run.exitCode ?? 1);
