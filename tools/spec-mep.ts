// Compiles the MEP contract in spec/mep/contract and refreshes the committed
// IR in spec/mep/generated/mep.ir.json.
//
// Usage (from the parent repository root):
//
//   bun run tools/spec-mep.ts        # or: mise run spec:mep
//
// The compile runs like the mep_contract test in crates/morphir: every
// MORPHIR_* variable removed and a temporary HOME, USERPROFILE,
// XDG_CONFIG_HOME, APPDATA, LOCALAPPDATA and MORPHIR_HOME, so a developer's
// config cannot change the committed bytes. Cargo builds the CLI first with
// the real environment, so it still finds the toolchain, and reports where
// the binary is, so a custom target directory works. The CLI writes the IR
// under the project directory that --config names; this script clears that
// output first so no cached state carries over.
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** The process environment with every MORPHIR_* variable removed, in any
 * case, and every home and config directory moved under `root`. */
export function isolatedEnvironment(
	env: Record<string, string | undefined>,
	root: string,
): Record<string, string> {
	const kept = Object.entries(env).filter(
		(entry): entry is [string, string] =>
			entry[1] !== undefined && entry[0].slice(0, 8).toUpperCase() !== "MORPHIR_",
	);
	const home = path.join(root, "home");
	return {
		...Object.fromEntries(kept),
		HOME: home,
		USERPROFILE: home,
		XDG_CONFIG_HOME: path.join(home, ".config"),
		APPDATA: path.join(home, "AppData", "Roaming"),
		LOCALAPPDATA: path.join(home, "AppData", "Local"),
		MORPHIR_HOME: path.join(root, "morphir-home"),
		MORPHIR_LOG_FILE: "false",
	};
}

type CargoMessage = {
	reason?: string;
	target?: { name?: string; kind?: string[] };
	executable?: string | null;
};

/** The path of the morphir binary in `cargo build --message-format=json`
 * output. */
export function builtExecutable(messages: string): string {
	let executable: string | undefined;
	for (const line of messages.split(/\r?\n/)) {
		let message: CargoMessage;
		try {
			message = JSON.parse(line) as CargoMessage;
		} catch {
			continue;
		}
		if (
			message.reason === "compiler-artifact" &&
			message.target?.name === "morphir" &&
			message.target.kind?.includes("bin") &&
			message.executable
		) {
			executable = message.executable;
		}
	}
	if (executable === undefined) throw new Error("cargo reported no morphir binary");
	return executable;
}

function run(command: string, args: string[], options: { cwd: string; env?: Record<string, string> }): string {
	const result = spawnSync(command, args, {
		cwd: options.cwd,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "inherit"],
		windowsHide: true,
	});
	if (result.error) throw result.error;
	if (result.status !== 0) {
		process.stdout.write(result.stdout ?? "");
		throw new Error(`${command} ${args.join(" ")} exited with status ${result.status}`);
	}
	return result.stdout;
}

if (import.meta.main) {
	const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
	const contract = path.join(repositoryRoot, "spec", "mep", "contract");
	const generated = path.join(repositoryRoot, "spec", "mep", "generated");

	const morphir = builtExecutable(
		run(
			"cargo",
			["build", "--locked", "-p", "morphir", "--bin", "morphir", "--message-format=json-render-diagnostics"],
			{ cwd: repositoryRoot },
		),
	);

	const isolated = mkdtempSync(path.join(tmpdir(), "spec-mep-"));
	try {
		mkdirSync(path.join(isolated, "home"), { recursive: true });
		rmSync(path.join(contract, ".morphir"), { recursive: true, force: true });
		process.stdout.write(
			run(
				morphir,
				["compile", "--config", path.join(contract, "morphir.toml"), "--ir-version", "4", "--types-only"],
				{ cwd: repositoryRoot, env: isolatedEnvironment(process.env, isolated) },
			),
		);
		mkdirSync(generated, { recursive: true });
		copyFileSync(
			path.join(contract, ".morphir", "out", "compile.dest", "morphir-ir.json"),
			path.join(generated, "mep.ir.json"),
		);
	} finally {
		rmSync(isolated, { recursive: true, force: true });
	}
}
