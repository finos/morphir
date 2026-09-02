import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
	demoEnvironment,
	execute,
	nativePackage,
	parseMode,
	prepareDemo,
	runDemo,
	type Runner,
} from "./demo-desktop";

const roots: string[] = [];
afterEach(() => {
	for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("selects native portable archives and rejects unsupported hosts", () => {
	expect(nativePackage("win32", "arm64")).toEqual({
		flag: "--win",
		target: "zip",
		os: "win",
		arch: "arm64",
	});
	expect(nativePackage("darwin", "x64").target).toBe("zip");
	expect(nativePackage("linux", "x64").target).toBe("tar.gz");
	expect(() => nativePackage("freebsd", "x64")).toThrow("Unsupported");
	expect(() => nativePackage("win32", "ia32")).toThrow("Unsupported");
});

test("only accepts interactive, prepare-only and help modes", () => {
	expect(parseMode([])).toBe("interactive");
	expect(parseMode(["--prepare-only"])).toBe("prepare");
	expect(parseMode(["--help"])).toBe("help");
	expect(() => parseMode(["--oops"])).toThrow("Usage");
	expect(() => parseMode(["--prepare-only", "--oops"])).toThrow("Usage");
});

test("isolates Home, profile and logs without mutating inherited environment", () => {
	const inherited = {
		MORPHIR_HOME: "personal",
		morphir_log_dir: "personal-logs",
		MORPHIR_LOG_FILE: "false",
		ELECTRON_RUN_AS_NODE: "1",
		PATH: "tools",
	};
	const env = demoEnvironment("demo", inherited);
	expect(env.MORPHIR_HOME).toBe(path.join("demo", "home"));
	expect(env.APPDATA).toBe(path.join("demo", "profile", "appdata"));
	expect(env.PATH).toBe("tools");
	expect(env).not.toHaveProperty("morphir_log_dir");
	expect(env).not.toHaveProperty("MORPHIR_LOG_FILE");
	expect(env).not.toHaveProperty("ELECTRON_RUN_AS_NODE");
	expect(inherited.MORPHIR_HOME).toBe("personal");
});

function fixture() {
	const root = mkdtempSync(path.join(tmpdir(), "morphir-demo-test-"));
	roots.push(root);
	const repo = path.join(root, "repository with spaces");
	const ui = path.join(repo, "ecosystem", "morphir-ui");
	const app = path.join(ui, "apps", "morphir-desktop");
	mkdirSync(app, { recursive: true });
	writeFileSync(path.join(app, "package.json"), JSON.stringify({ version: "0.1.0" }));
	const fixtureDir = path.join(ui, "packages", "morphir-ir", "test", "fixtures");
	mkdirSync(fixtureDir, { recursive: true });
	writeFileSync(path.join(fixtureDir, "insight-ir.json"), "sample model");
	const cli = path.join(root, "compiled-cli");
	writeFileSync(cli, "compiled CLI");
	const calls: Parameters<Runner>[0][] = [];
	const run: Runner = async (command) => {
		calls.push(command);
		if (command.args[0] === "cargo")
			return JSON.stringify({
				reason: "compiler-artifact",
				target: { name: "morphir", kind: ["bin"] },
				executable: cli,
			});
		if (command.args.includes("electron-builder")) {
			const output = command.args
				.find((arg) => arg.startsWith("--config.directories.output="))!
				.split("=")
				.slice(1)
				.join("=");
			mkdirSync(output, { recursive: true });
			writeFileSync(path.join(output, "morphir-desktop-0.1.0-win-arm64.zip"), "package");
		}
		return "";
	};
	return { root, repo, calls, run };
}

test("prepares a fresh demo using argv arrays and the public verified install", async () => {
	const f = fixture();
	const demo = await prepareDemo(
		{ repositoryRoot: f.repo, temporaryRoot: f.root, platform: "win32", arch: "arm64" },
		f.run,
	);
	expect(path.dirname(demo.root)).toBe(f.root);
	expect(readFileSync(demo.executable, "utf8")).toBe("compiled CLI");
	expect(readFileSync(demo.workspace, "utf8")).toBe("sample model");
	expect(f.calls.at(-1)?.args).toEqual([
		demo.executable,
		"tool",
		"install",
		"desktop",
		"--source",
		demo.packagePath,
		"--channel",
		"developer",
		"--version",
		"0.1.0",
	]);
	expect(f.calls.at(-1)?.cwd).toBe(demo.root);
	expect(f.calls.at(-1)?.env?.MORPHIR_HOME).toBe(path.join(demo.root, "home"));
	expect(f.calls.some((call) => call.args[1] === "desktop")).toBe(false);
	expect(f.calls.find((call) => call.args.includes("electron-builder"))?.args).toContain(
		"--publish=never",
	);
});

test("repeats offline outside checkout only after the first exit and hides the original package", async () => {
	const f = fixture();
	const demo = await prepareDemo(
		{ repositoryRoot: f.repo, temporaryRoot: f.root, platform: "win32", arch: "arm64" },
		f.run,
	);
	let launches = 0;
	await runDemo(demo, async (command) => {
		expect(command.args).toEqual([
			demo.executable,
			"desktop",
			"--offline",
			"--wait",
			demo.workspace,
		]);
		expect(command.cwd).toBe(demo.root);
		expect(existsSync(demo.packagePath)).toBe(launches === 0);
		launches++;
		return "";
	});
	expect(launches).toBe(2);
	expect(readFileSync(path.join(demo.root, "package.saved"), "utf8")).toBe("package");
});

test("failed launch prevents package move and second launch", async () => {
	const f = fixture();
	const demo = await prepareDemo(
		{ repositoryRoot: f.repo, temporaryRoot: f.root, platform: "win32", arch: "arm64" },
		f.run,
	);
	let launches = 0;
	await expect(
		runDemo(demo, async () => {
			launches++;
			throw new Error("exit 17");
		}),
	).rejects.toThrow("exit 17");
	expect(launches).toBe(1);
	expect(existsSync(demo.packagePath)).toBe(true);
});

test("build failure prevents package installation", async () => {
	const f = fixture();
	await expect(
		prepareDemo(
			{ repositoryRoot: f.repo, temporaryRoot: f.root, platform: "win32", arch: "arm64" },
			async () => {
				throw new Error("build failed");
			},
		),
	).rejects.toThrow("build failed");
	expect(f.calls).toHaveLength(0);
});

test("subprocess failures preserve the actual exit code", async () => {
	await expect(
		execute({ args: [process.execPath, "-e", "process.exit(17)"], cwd: tmpdir() }),
	).rejects.toMatchObject({ exitCode: 17 });
});
