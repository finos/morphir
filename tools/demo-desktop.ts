import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const usage = "Usage: mise run demo:desktop -- [--prepare-only | --help]";
type Environment = Readonly<Record<string, string | undefined>>;
interface Command {
	readonly args: readonly string[];
	readonly cwd: string;
	readonly env?: Environment;
	readonly output?: "capture" | "inherit";
}
export type Runner = (command: Command) => Promise<string>;

export function parseMode(args: readonly string[]): "interactive" | "prepare" | "help" {
	if (args.length === 0) return "interactive";
	if (args.length === 1 && args[0] === "--prepare-only") return "prepare";
	if (args.length === 1 && args[0] === "--help") return "help";
	throw new Error(usage);
}

export function nativePackage(platform: string, arch: string) {
	if (arch !== "arm64" && arch !== "x64")
		throw new Error(`Unsupported Desktop demo architecture: ${arch}`);
	switch (platform) {
		case "win32":
			return { flag: "--win", target: "zip", os: "win", arch } as const;
		case "darwin":
			return { flag: "--mac", target: "zip", os: "mac", arch } as const;
		case "linux":
			return { flag: "--linux", target: "tar.gz", os: "linux", arch } as const;
		default:
			throw new Error(`Unsupported Desktop demo platform: ${platform}`);
	}
}

export function demoEnvironment(root: string, inherited: Environment): Environment {
	const env = Object.fromEntries(
		Object.entries(inherited).filter(
			([key]) =>
				!key.toUpperCase().startsWith("MORPHIR_") && key.toUpperCase() !== "ELECTRON_RUN_AS_NODE",
		),
	);
	return {
		...env,
		MORPHIR_HOME: path.join(root, "home"),
		APPDATA: path.join(root, "profile", "appdata"),
		LOCALAPPDATA: path.join(root, "profile", "local"),
		XDG_CONFIG_HOME: path.join(root, "profile", "config"),
	};
}

function unsignedBuildEnvironment(): Environment {
	return {
		...Object.fromEntries(
			Object.entries(process.env).filter(
				([key]) =>
					!key.toUpperCase().startsWith("CSC_") && !key.toUpperCase().startsWith("WIN_CSC_"),
			),
		),
		CSC_IDENTITY_AUTO_DISCOVERY: "false",
	};
}

class CommandFailure extends Error {
	constructor(
		readonly exitCode: number,
		args: readonly string[],
	) {
		super(`Command exited ${exitCode}: ${args.join(" ")}`);
	}
}

export const execute: Runner = async ({ args, cwd, env, output = "inherit" }) => {
	const child = Bun.spawn([...args], {
		cwd,
		env,
		stdin: "inherit",
		stderr: "inherit",
		stdout: output === "capture" ? "pipe" : "inherit",
	});
	const stdout = output === "capture" ? await new Response(child.stdout).text() : "";
	const exitCode = await child.exited;
	if (exitCode !== 0) throw new CommandFailure(exitCode, args);
	return stdout;
};

function builtCli(output: string): string {
	for (const line of output.split(/\r?\n/).filter(Boolean).reverse()) {
		const value = JSON.parse(line);
		if (
			value.reason === "compiler-artifact" &&
			value.target?.name === "morphir" &&
			value.target?.kind?.includes("bin") &&
			typeof value.executable === "string"
		)
			return value.executable;
	}
	throw new Error("Cargo did not report a built morphir executable");
}

interface Demo {
	readonly root: string;
	readonly executable: string;
	readonly workspace: string;
	readonly packagePath: string;
	readonly env: Environment;
}

export async function prepareDemo(
	options: {
		readonly repositoryRoot: string;
		readonly temporaryRoot: string;
		readonly platform: string;
		readonly arch: string;
	},
	run: Runner = execute,
): Promise<Demo> {
	const target = nativePackage(options.platform, options.arch);
	const ui = path.join(options.repositoryRoot, "ecosystem", "morphir-ui");
	const app = path.join(ui, "apps", "morphir-desktop");
	const manifest = JSON.parse(readFileSync(path.join(app, "package.json"), "utf8"));
	if (
		typeof manifest.version !== "string" ||
		!/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(manifest.version)
	) {
		throw new Error("Desktop package.json must contain a valid version");
	}
	const root = mkdtempSync(path.join(options.temporaryRoot, "morphir-demo-"));
	console.log(`Demo files and logs will be retained at: ${root}`);
	const env = demoEnvironment(root, process.env);
	for (const directory of [
		"bin",
		"home",
		"workspace",
		"profile/appdata",
		"profile/local",
		"profile/config",
	]) {
		mkdirSync(path.join(root, directory), { recursive: true });
	}
	const executable = path.join(
		root,
		"bin",
		options.platform === "win32" ? "morphir.exe" : "morphir",
	);
	const workspace = path.join(root, "workspace", "morphir-ir.json");
	copyFileSync(
		path.join(ui, "packages", "morphir-ir", "test", "fixtures", "insight-ir.json"),
		workspace,
	);
	const compilation = await run({
		args: [
			"cargo",
			"build",
			"--locked",
			"-p",
			"morphir",
			"--bin",
			"morphir",
			"--message-format=json",
		],
		cwd: options.repositoryRoot,
		output: "capture",
	});
	copyFileSync(builtCli(compilation), executable);
	await run({ args: ["bun", "install", "--frozen-lockfile"], cwd: ui });
	await run({ args: ["bun", "run", "build"], cwd: app });
	const packages = path.join(root, "package");
	await run({
		args: [
			"bunx",
			"--no-install",
			"electron-builder",
			target.flag,
			target.target,
			`--${target.arch}`,
			"--publish=never",
			"--config.mac.notarize=false",
			"--config.extraMetadata.morphirBuildChannel=developer",
			`--config.directories.output=${packages}`,
		],
		cwd: app,
		env: unsignedBuildEnvironment(),
	});
	const packagePath = path.join(
		packages,
		`morphir-desktop-${manifest.version}-${target.os}-${target.arch}.${target.target}`,
	);
	await run({
		args: [
			executable,
			"tool",
			"install",
			"desktop",
			"--source",
			packagePath,
			"--channel",
			"developer",
			"--version",
			manifest.version,
		],
		cwd: root,
		env,
	});
	return { root, executable, workspace, packagePath, env };
}

export async function runDemo(demo: Demo, run: Runner = execute): Promise<void> {
	const command = {
		args: [demo.executable, "desktop", "--offline", "--wait", demo.workspace],
		cwd: demo.root,
		env: demo.env,
	};
	console.log(
		"First launch: open IR Explorer, select applyLambda and inspect Insight/XRay. Close Desktop to continue.",
	);
	await run(command);
	// Move only the package generated in this fresh demo directory; never delete user data.
	renameSync(demo.packagePath, path.join(demo.root, "package.saved"));
	console.log(
		"Second launch: original package path is absent. Inspect the model, then close Desktop.",
	);
	await run(command);
	console.log(`Both commands exited successfully. Logs: ${path.join(demo.root, "home", "logs")}`);
	console.log("This demo does not block networking or make the source checkout unreadable.");
}

async function main(): Promise<void> {
	const mode = parseMode(process.argv.slice(2));
	if (mode === "help") {
		console.log(
			`${usage}\nBuild and install an unsigned native Desktop in a fresh temporary Home.\nDefault: two interactive offline launches. --prepare-only: install without opening a window.\nPrerequisites: initialized submodules, Rust, Bun and native build tools. Builds may use the network.\nArtifacts and logs are retained; existing installations are not changed.`,
		);
		return;
	}
	const demo = await prepareDemo({
		repositoryRoot: path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."),
		temporaryRoot: tmpdir(),
		platform: process.platform,
		arch: process.arch,
	});
	if (mode === "interactive") await runDemo(demo);
}

if (import.meta.main) {
	main().catch((error: unknown) => {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = error instanceof CommandFailure ? error.exitCode : 1;
	});
}
