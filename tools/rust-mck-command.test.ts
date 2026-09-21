import { expect, test } from "bun:test";
import path from "node:path";
import { rustMckInvocation } from "./rust-mck-command.ts";

test("retired IR routes direct callers to the native CLI", () => {
	for (const args of [[], ["--kit", "kit"], ["--suite", "ir"]]) {
		expect(() => rustMckInvocation("/repo", "linux", args)).toThrow("morphir mck");
	}
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

test("Windows uses the executable suffix", () => {
	expect(rustMckInvocation("/repo", "win32", ["--suite", "package"]).adapter).toEndWith("mck-adapter-rust.exe");
	expect(rustMckInvocation("/repo", "darwin", ["--suite", "package"]).adapter).toEndWith("mck-adapter-rust");
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
	]) {
		expect(() => rustMckInvocation("/repo", "linux", args)).toThrow("contract");
	}
});

test("a recorded package run still selects the adapter's package contract", () => {
	const result = rustMckInvocation("/repo", "linux", [
		"--suite", "package", "--contract", "0.1.0-draft.2", "--record", "t.ndjson",
	]);
	expect(result.command.slice(2)).toEqual([
		"package", "run", "--adapter", "bun",
		"--adapter-arg", path.join("/repo", "tools/record-mck-transcript.ts"),
		"--adapter-arg", "t.ndjson",
		"--adapter-arg", result.adapter,
		"--adapter-arg", "--suite", "--adapter-arg", "package",
		"--adapter-arg", "--contract", "--adapter-arg", "0.1.0-draft.2",
		"--contract", "0.1.0-draft.2",
	]);
});

test("rejects duplicate or malformed recording selection", () => {
	for (const args of [["--record"], ["--record", "--kit", "kit"], ["--record=t.ndjson"],
		["--record", "a.ndjson", "--record", "b.ndjson"]]) {
		expect(() => rustMckInvocation("/repo", "linux", ["--suite", "package", ...args])).toThrow("record");
	}
});

test("caller cannot replace the platform-resolved adapter", () => {
	for (const args of [["--adapter", "other"], ["--adapter=other"]]) {
		expect(() => rustMckInvocation("/repo", "linux", ["--suite", "package", ...args])).toThrow("supplies --adapter");
	}
});
