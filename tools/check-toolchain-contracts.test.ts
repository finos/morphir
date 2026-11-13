import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkContracts, sourceInfo, type Execute } from "./check-toolchain-contracts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (file: string) => readFileSync(resolve(root, file), "utf8");

test("acquisition behavior has no second Rust reference implementation", () => {
	// This repository holds no Rust workspace; the development tools are in
	// the ecosystem/morphir-rust submodule (umbrella-tools).
	expect(existsSync(resolve(root, "crates"))).toBe(false);
	expect(existsSync(resolve(root, "Cargo.lock"))).toBe(false);
	expect(read(".config/mise/config.toml")).not.toContain("--package morphir-toolchain-contract");
});

test("parent CI requires the .NET acquisition check when its corpus changes", () => {
	const workflow = read(".github/workflows/ci.yml");
	expect(workflow.includes("toolchain-contracts:")).toBe(true);
	expect(workflow.includes("tools/check-toolchain-contracts.ts")).toBe(true);
	expect(workflow.includes('require "${{ needs.changes.outputs.toolchain-contracts }}" toolchain-contracts')).toBe(true);
	expect(workflow).not.toContain("run: mise run ci:validate-toolchain-contracts");
});

const scratch: string[] = [];
afterEach(() => {
	for (const path of scratch.splice(0)) {
		if (resolve(path) !== path || !path.startsWith(join(tmpdir(), "morphir-contract-gate-"))) {
			throw new Error(`Refusing unexpected scratch cleanup: ${path}`);
		}
		rmSync(path, { recursive: true, force: true });
	}
});

const commit = "a".repeat(40);
function fixture() {
	const path = mkdtempSync(join(tmpdir(), "morphir-contract-gate-"));
	scratch.push(path);
	const parent = join(path, "parent with spaces");
	const source = join(path, "dotnet with spaces");
	const files = {
		".config/toolchain-contract-tests.json": JSON.stringify({ repository: "finos/morphir-dotnet", commit }),
		"docs/spec/toolchain/fixtures/0.1.0-draft.1/cases.json": "{}",
		"docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/cases.json": "{}",
		"docs/spec/toolchain/fixtures/0.1.0-draft.1/contract-files.json": "{}",
	};
	for (const [file, content] of Object.entries(files)) {
		mkdirSync(dirname(join(parent, file)), { recursive: true });
		writeFileSync(join(parent, file), content);
	}
	const project = join(source, "tests/Morphir.Toolchain.Tests/Morphir.Toolchain.Tests.fsproj");
	mkdirSync(dirname(project), { recursive: true });
	writeFileSync(project, "<Project />");
	return { parent, source };
}

function executor(parent: string, options: { head?: string; dirty?: boolean; exit?: number; marker?: boolean; preamble?: string } = {}) {
	const calls: { command: string; args: string[]; cwd: string; env: NodeJS.ProcessEnv }[] = [];
	const execute: Execute = (command, args, context) => {
		calls.push({ command, args, ...context });
		if (args.includes("rev-parse")) return { status: 0, stdout: `${options.head ?? commit}\n`, stderr: "" };
		if (args.includes("status")) return { status: 0, stdout: options.dirty ? " M src/Reader.fs\n" : "", stderr: "" };
		return {
			status: options.exit ?? 0,
			stdout: options.marker === false ? "Tests passed\n" : `${options.preamble ?? ""}External toolchain corpus: ${parent}\nTests passed\n`,
			stderr: "",
		};
	};
	return { execute, calls };
}

test("a floating source ref is refused", () => {
	const { parent } = fixture();
	writeFileSync(join(parent, ".config/toolchain-contract-tests.json"), JSON.stringify({ repository: "finos/morphir-dotnet", commit: "main" }));
	expect(() => sourceInfo(parent)).toThrow("40-character");
});

test("a different source commit cannot validate the parent", () => {
	const { parent, source } = fixture();
	const { execute, calls } = executor(parent, { head: "b".repeat(40) });
	expect(() => checkContracts(parent, source, execute)).toThrow("source commit");
	expect(calls.every((call) => !call.args.includes("build"))).toBe(true);
});

test("modified source cannot claim evidence for its pin", () => {
	const { parent, source } = fixture();
	const { execute } = executor(parent, { dirty: true });
	expect(() => checkContracts(parent, source, execute)).toThrow("tracked changes");
});

test("missing current cases fail before any build instead of falling back to the source pin", () => {
	const { parent, source } = fixture();
	rmSync(join(parent, "docs/spec/toolchain/fixtures/0.1.0-draft.1/cases.json"));
	const { execute, calls } = executor(parent);
	expect(() => checkContracts(parent, source, execute)).toThrow("cases.json");
	expect(calls).toHaveLength(0);
});

test("the actual source tests receive the absolute parent corpus and retain their failure", () => {
	const { parent, source } = fixture();
	const { execute, calls } = executor(parent, { exit: 7 });
	// A successful build followed by a failing suite.
	const run: Execute = (command, args, context) => args.includes("build")
		? { status: 0, stdout: "", stderr: "" }
		: execute(command, args, context);
	expect(checkContracts(parent, source, run).status).toBe(7);
	const testRun = calls.find((call) => call.args.includes("exec"));
	expect(testRun?.cwd).toBe(source);
	expect(testRun?.env.MORPHIR_TOOLCHAIN_CONTRACT_ROOT).toBe(parent);
	expect(testRun?.args).toContain("--sequenced");
});

test("old pinned tests passing without acknowledging the external corpus are refused", () => {
	const { parent, source } = fixture();
	const { execute } = executor(parent, { marker: false });
	expect(() => checkContracts(parent, source, execute)).toThrow("external corpus");
});

test("a late marker cannot acknowledge a different test path", () => {
	const { parent, source } = fixture();
	const { execute } = executor(parent, { preamble: "Testing the pinned corpus instead\n" });
	expect(() => checkContracts(parent, source, execute)).toThrow("external corpus");
});

test("changes to the pinned license and notice select the contract check", () => {
	const filter = read(".github/workflows/ci.yml").split("            toolchain-contracts:\n")[1]?.split("            rust-conformance:")[0] ?? "";
	for (const file of ["LICENSE", "NOTICE"]) expect(filter.includes(`- '${file}'`)).toBe(true);
});
