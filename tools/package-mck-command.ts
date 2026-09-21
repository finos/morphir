import path from "node:path";

/** CI orchestration only: the native CLI owns every case and verdict. */
export function packageMckInvocation(root: string, platform: string, args: readonly string[]): { command: string[]; report: string } {
	const [binding, contract] = args;
	if (args.length !== 2 || (binding !== "typescript" && binding !== "rust") || (contract !== "0.1.0-draft.1" && contract !== "0.1.0-draft.2")) {
		throw new Error("usage: run-package-mck <typescript|rust> <0.1.0-draft.1|0.1.0-draft.2>");
	}
	const prefix = contract === "0.1.0-draft.1" ? "package" : "package-resolution";
	const report = path.join(root, ".dev/out/mck", `${prefix}-${binding === "typescript" ? "typescript-adapter" : "rust"}.json`);
	const adapter = binding === "typescript" ? "bun" : path.join(root, "ecosystem/morphir-rust/target/debug", platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust");
	const adapterArgs = [
		...(binding === "typescript" ? [path.join(root, "ecosystem/morphir-typescript/packages/mck/src/adapter.ts")] : []),
		"--suite", "package", "--contract", contract,
	];
	return { report, command: [
		"cargo", "run", "--locked", "--package", "morphir", "--", "mck", "package", "run",
		"--kit", path.join(root, "spec/package/mck"), "--contract", contract, "--adapter", adapter,
		...adapterArgs.flatMap(arg => ["--adapter-arg", arg]), "--report", report,
	] };
}

export function packageProcessExitCode(result: { exitCode: number; signalCode?: string | null }): number {
	return result.signalCode ? 1 : result.exitCode;
}
