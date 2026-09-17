import { expect, test } from "bun:test";
import path from "node:path";
import { rustMckInvocation } from "./rust-mck-command.ts";

test("default invocation preserves the IR driver command", () => {
	const result = rustMckInvocation("/repo", "linux", ["--kit", "kit", "--report", "report.json"]);
	expect(result.command).toEqual([
		"bun", path.join("/repo", "ecosystem/morphir-typescript/packages/mck/src/cli.ts"),
		"run", "--adapter", result.adapter, "--kit", "kit", "--report", "report.json",
	]);
});

test("package suite selects both driver and adapter package contracts", () => {
	const result = rustMckInvocation("/repo", "linux", ["--suite", "package", "--kit", "kit"]);
	expect(result.command.slice(2)).toEqual([
		"package", "run", "--adapter", result.adapter,
		"--adapter-arg", "--suite", "--adapter-arg", "package", "--kit", "kit",
	]);
});

test("package contract selection reaches the Linux driver and adapter", () => {
	const result = rustMckInvocation("/repo", "linux", [
		"--suite", "package", "--contract", "0.1.0-draft.2", "--kit", "kit",
	]);
	expect(result.adapter).toEndWith("mck-adapter-rust");
	expect(result.command.slice(2)).toEqual([
		"package", "run", "--adapter", result.adapter,
		"--adapter-arg", "--suite", "--adapter-arg", "package",
		"--adapter-arg", "--contract", "--adapter-arg", "0.1.0-draft.2",
		"--contract", "0.1.0-draft.2", "--kit", "kit",
	]);
});

test("package contract selection reaches the Windows driver and adapter", () => {
	const result = rustMckInvocation("C:\\repo", "win32", [
		"--suite", "package", "--contract", "0.1.0-draft.2", "--kit", "kit",
	]);
	expect(result.adapter).toEndWith("mck-adapter-rust.exe");
	expect(result.command.slice(2)).toEqual([
		"package", "run", "--adapter", result.adapter,
		"--adapter-arg", "--suite", "--adapter-arg", "package",
		"--adapter-arg", "--contract", "--adapter-arg", "0.1.0-draft.2",
		"--contract", "0.1.0-draft.2", "--kit", "kit",
	]);
});

test("explicit IR selection preserves the default command", () => {
	expect(rustMckInvocation("/repo", "linux", ["--suite", "ir"]).command)
		.toEqual(rustMckInvocation("/repo", "linux", []).command);
});

test("Windows uses the executable suffix", () => {
	expect(rustMckInvocation("/repo", "win32", []).adapter).toEndWith("mck-adapter-rust.exe");
	expect(rustMckInvocation("/repo", "darwin", []).adapter).toEndWith("mck-adapter-rust");
});

test("rejects invalid or ambiguous suite selection", () => {
	for (const args of [["--suite"], ["--suite", "other"], ["--suite=package"],
		["--kit", "kit", "--suite", "package"], ["--suite", "package", "--suite", "ir"]]) {
		expect(() => rustMckInvocation("/repo", "linux", args)).toThrow();
	}
});

test("rejects duplicate, conflicting, or malformed contract selection", () => {
	for (const args of [
		["--suite", "package", "--contract"],
		["--suite", "package", "--contract", "--kit", "kit"],
		["--suite", "package", "--contract=0.1.0-draft.2"],
		["--suite", "package", "--contract", "0.1.0-draft.2", "--contract", "0.1.0-draft.2"],
		["--suite", "package", "--contract", "0.1.0-draft.2", "--contract", "0.1.0-draft.1"],
		["--contract", "0.1.0-draft.2"],
		["--suite", "ir", "--contract", "0.1.0-draft.2"],
	]) {
		expect(() => rustMckInvocation("/repo", "linux", args)).toThrow("contract");
	}
});

test("caller cannot replace the platform-resolved adapter", () => {
	for (const args of [["--adapter", "other"], ["--adapter=other"]]) {
		expect(() => rustMckInvocation("/repo", "linux", args)).toThrow("supplies --adapter");
	}
});
