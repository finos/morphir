// Completes a mise-managed Windows MoonBit archive with its stock core and moonx.
// Called by mise postinstall; never installs into the user's shared ~/.moon.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";

type ProcessResult = { status: number | null; stdout: string; stderr: string; error?: Error };

export type BootstrapDependencies = {
	run?: (command: string, args: string[], environment: NodeJS.ProcessEnv) => ProcessResult;
	download?: (url: string) => Promise<Uint8Array>;
	environment?: NodeJS.ProcessEnv;
};

type BootstrapOptions = { toolchainHome: string; version: string; coreSha256: string };

function isFile(filename: string): boolean {
	return statSync(filename, { throwIfNoEntry: false })?.isFile() ?? false;
}

/** Finish only the explicitly selected mise installation. Dependencies let tests
 * exercise download and process failures without a Windows host or network. */
export async function bootstrapMoonBit(
	{ toolchainHome, version, coreSha256 }: BootstrapOptions,
	dependencies: BootstrapDependencies = {},
): Promise<void> {
	if (!toolchainHome) throw new Error("An explicit mise toolchain directory is required");
	if (!version) throw new Error("MISE_TOOL_VERSION must name the pinned MoonBit version");
	if (!/^[a-fA-F0-9]{64}$/.test(coreSha256)) throw new Error("A SHA256 core checksum is required");
	const moon = path.join(toolchainHome, "bin", "moon.exe");
	if (!isFile(moon)) throw new Error("Install the pinned compiler archive first");
	const environment: NodeJS.ProcessEnv = { ...(dependencies.environment ?? process.env), MOON_HOME: toolchainHome };
	const run = dependencies.run ?? ((command, args, env) => spawnSync(command, args, { env, encoding: "utf8" }));
	const checkedRun = (command: string, args: string[], env = environment): string => {
		const result = run(command, args, env);
		if (result.error) throw result.error;
		if (result.status !== 0) {
			throw new Error(`${path.basename(command)} failed (exit ${result.status}): ${result.stderr.trim() || result.stdout.trim()}`);
		}
		return result.stdout;
	};
	const compiler = checkedRun(path.join(toolchainHome, "bin", "moonc.exe"), ["-v"]);
	if (!compiler.startsWith(`v${version} `)) throw new Error("The pinned compiler is required before core setup");
	const lib = path.join(toolchainHome, "lib");
	const core = path.join(lib, "core");
	if (!isFile(path.join(core, "moon.mod"))) {
		const temporaryDirectory = mkdtempSync(path.join(toolchainHome, "bootstrap-core-"));
		try {
			const url = `https://cli.moonbitlang.com/cores/core-${encodeURIComponent(version)}.zip`;
			const download = dependencies.download ?? (async (archiveUrl) => {
				const response = await fetch(archiveUrl);
				if (!response.ok) throw new Error(`Core download failed: HTTP ${response.status}`);
				return new Uint8Array(await response.arrayBuffer());
			});
			const bytes = await download(url);
			const archive = path.join(temporaryDirectory, "core.zip");
			writeFileSync(archive, bytes);
			if (createHash("sha256").update(bytes).digest("hex") !== coreSha256.toLowerCase()) {
				throw new Error("Bootstrap core checksum differs");
			}
			mkdirSync(lib, { recursive: true });
			// Pass paths through the child environment so spaces, quotes and shell
			// metacharacters cannot become PowerShell source code.
			checkedRun("powershell.exe", [
				"-NoProfile", "-NonInteractive", "-Command",
				"$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:MORPHIR_MOONBIT_ARCHIVE -DestinationPath $env:MORPHIR_MOONBIT_LIB",
			], { ...environment, MORPHIR_MOONBIT_ARCHIVE: archive, MORPHIR_MOONBIT_LIB: lib });
		} finally {
			rmSync(temporaryDirectory, { recursive: true, force: true });
		}
	}
	const moonx = path.join(toolchainHome, "bin", "moonx.exe");
	if (!isFile(moonx)) copyFileSync(moon, moonx);
	checkedRun(moon, ["-C", core, "bundle", "--warn-list", "-a", "--all"]);
}

if (import.meta.main) {
	try {
		const { values } = parseArgs({ options: { "core-sha256": { type: "string" } } });
		await bootstrapMoonBit({
			toolchainHome: process.env.MISE_TOOL_INSTALL_PATH ?? "",
			version: process.env.MISE_TOOL_VERSION ?? "",
			coreSha256: values["core-sha256"] ?? "",
		});
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	}
}
