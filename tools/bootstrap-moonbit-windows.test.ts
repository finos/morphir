import { afterEach, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { bootstrapMoonBit, type BootstrapDependencies } from "./bootstrap-moonbit-windows";

const version = "0.10.16+b1a0e846e";
const archive = new TextEncoder().encode("verified core archive");
const checksum = createHash("sha256").update(archive).digest("hex");
const temporaryDirectories: string[] = [];

afterEach(() => {
	for (const directory of temporaryDirectories.splice(0)) rmSync(directory, { recursive: true, force: true });
});

function fixture() {
	const home = mkdtempSync(path.join(tmpdir(), "moonbit-windows-"));
	temporaryDirectories.push(home);
	mkdirSync(path.join(home, "bin"));
	writeFileSync(path.join(home, "bin", "moon.exe"), "moon executable");
	const calls: { command: string; args: string[]; environment: NodeJS.ProcessEnv }[] = [];
	const downloads: string[] = [];
	const environment = { MOON_HOME: "existing shared home", PATH: "existing path" };
	let compilerVersion = `v${version} (compiler metadata)`;
	let bundleStatus = 0;
	const dependencies: BootstrapDependencies = {
		environment,
		download: async (url) => {
			downloads.push(url);
			return archive;
		},
		run: (command, args, env) => {
			calls.push({ command, args, environment: env });
			if (command.endsWith("moonc.exe")) return { status: 0, stdout: compilerVersion, stderr: "" };
			if (command === "powershell.exe") {
				expect(readFileSync(env.MORPHIR_MOONBIT_ARCHIVE!)).toEqual(Buffer.from(archive));
				mkdirSync(path.join(env.MORPHIR_MOONBIT_LIB!, "core"), { recursive: true });
				writeFileSync(path.join(env.MORPHIR_MOONBIT_LIB!, "core", "moon.mod"), "{}");
				return { status: 0, stdout: "", stderr: "" };
			}
			return { status: bundleStatus, stdout: "", stderr: bundleStatus ? "bundle diagnostic" : "" };
		},
	};
	return {
		home,
		calls,
		downloads,
		environment,
		dependencies,
		options: { toolchainHome: home, version, coreSha256: checksum },
		setCompilerVersion: (value: string) => { compilerVersion = value; },
		setBundleStatus: (value: number) => { bundleStatus = value; },
	};
}

test("rejects an unexpected compiler before downloading or modifying core", async () => {
	const f = fixture();
	f.setCompilerVersion("v0.10.15+other (compiler metadata)");
	await expect(bootstrapMoonBit(f.options, f.dependencies)).rejects.toThrow("pinned compiler");
	expect(f.downloads).toEqual([]);
	expect(f.calls).toHaveLength(1);
	expect(existsSync(path.join(f.home, "lib"))).toBe(false);
});

test("rejects a checksum mismatch before extraction or bundling and removes the archive", async () => {
	const f = fixture();
	await expect(bootstrapMoonBit({ ...f.options, coreSha256: "0".repeat(64) }, f.dependencies))
		.rejects.toThrow("checksum");
	expect(f.calls).toHaveLength(1);
	expect(readdirSync(f.home)).toEqual(["bin"]);
	expect(existsSync(path.join(f.home, "bin", "moonx.exe"))).toBe(false);
});

test("installs matching core and moonx within the mise toolchain and can run again", async () => {
	const f = fixture();
	await bootstrapMoonBit(f.options, f.dependencies);
	expect(f.downloads).toEqual([
		"https://cli.moonbitlang.com/cores/core-0.10.16%2Bb1a0e846e.zip",
	]);
	expect(readFileSync(path.join(f.home, "bin", "moonx.exe"), "utf8")).toBe("moon executable");
	const bundle = f.calls.at(-1)!;
	expect(bundle.command).toBe(path.join(f.home, "bin", "moon.exe"));
	expect(bundle.args).toEqual(["-C", path.join(f.home, "lib", "core"), "bundle", "--warn-list", "-a", "--all"]);
	expect(bundle.environment.MOON_HOME).toBe(f.home);
	expect(bundle.environment.PATH).toBe("existing path");
	expect(f.environment.MOON_HOME).toBe("existing shared home");
	expect(readdirSync(f.home).sort()).toEqual(["bin", "lib"]);
	writeFileSync(path.join(f.home, "bin", "moonx.exe"), "existing moonx");
	await bootstrapMoonBit(f.options, f.dependencies);
	expect(f.downloads).toHaveLength(1);
	expect(f.calls.filter((call) => call.command === "powershell.exe")).toHaveLength(1);
	expect(readFileSync(path.join(f.home, "bin", "moonx.exe"), "utf8")).toBe("existing moonx");
});

test("propagates a nonzero core bundling exit with its diagnostic", async () => {
	const f = fixture();
	f.setBundleStatus(9);
	await expect(bootstrapMoonBit(f.options, f.dependencies)).rejects.toThrow("bundle diagnostic");
	expect(f.environment.MOON_HOME).toBe("existing shared home");
	expect(readdirSync(f.home).sort()).toEqual(["bin", "lib"]);
});

test("requires a mise installation instead of falling back to the shared MoonBit home", async () => {
	const f = fixture();
	await expect(bootstrapMoonBit({ ...f.options, toolchainHome: "" }, f.dependencies))
		.rejects.toThrow("explicit mise toolchain");
	expect(f.calls).toEqual([]);
});
