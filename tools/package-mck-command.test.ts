import { expect, test } from "bun:test";
import path from "node:path";
import { packageMckInvocation, packageProcessExitCode } from "./package-mck-command.ts";

const root = path.resolve("directory with spaces");
for (const contract of ["0.1.0-draft.1", "0.1.0-draft.2"]) {
	for (const binding of ["typescript", "rust"]) {
		test(`${binding} ${contract} uses native MCK with separate adapter arguments`, () => {
			const { command, report } = packageMckInvocation(root, "linux", [binding, contract]);
			expect(command.slice(0, 9)).toEqual(["cargo", "run", "--locked", "--package", "morphir", "--", "mck", "package", "run"]);
			const adapter = binding === "typescript" ? "bun" : path.join(root, "ecosystem/morphir-rust/target/debug/mck-adapter-rust");
			expect(command[command.indexOf("--adapter") + 1]).toBe(adapter);
			expect(command[command.indexOf("--kit") + 1]).toBe(path.join(root, "spec/package/mck"));
			const args = command.flatMap((arg, index) => arg === "--adapter-arg" ? [command[index + 1]] : []);
			expect(args).toEqual([
				...(binding === "typescript" ? [path.join(root, "ecosystem/morphir-typescript/packages/mck/src/adapter.ts")] : []),
				"--suite", "package", "--contract", contract,
			]);
			expect(command[command.indexOf("--contract") + 1]).toBe(contract);
			const prefix = contract === "0.1.0-draft.1" ? "package" : "package-resolution";
			expect(report).toBe(path.join(root, ".dev/out/mck", `${prefix}-${binding === "typescript" ? "typescript-adapter" : "rust"}.json`));
			expect(command.at(-1)).toBe(report);
		});
	}
}

test("Windows Rust adapter uses its executable suffix", () => {
	const { command } = packageMckInvocation(root, "win32", ["rust", "0.1.0-draft.2"]);
	expect(command[command.indexOf("--adapter") + 1]).toBe(path.join(root, "ecosystem/morphir-rust/target/debug/mck-adapter-rust.exe"));
});

for (const args of [[], ["typescript"], ["python", "0.1.0-draft.1"], ["rust", "0.1.0-draft.3"], ["rust", "0.1.0-draft.1", "--adapter", "other"]]) {
	test(`rejects unsupported or ambiguous selection ${JSON.stringify(args)}`, () => {
		expect(() => packageMckInvocation(root, "linux", args)).toThrow("usage:");
	});
}

test("a successful native subprocess remains a successful gate", () => {
	const result = Bun.spawnSync([process.execPath, "-e", "process.exit(0)"]);
	expect(packageProcessExitCode(result)).toBe(0);
});

test("nonzero native verdicts and signal termination fail the gate", () => {
	const result = Bun.spawnSync([process.execPath, "-e", "process.exit(2)"]);
	expect(packageProcessExitCode(result)).toBe(2);
	expect(packageProcessExitCode({ exitCode: 0, signalCode: "SIGTERM" })).toBe(1);
});
