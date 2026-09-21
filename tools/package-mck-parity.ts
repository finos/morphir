import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import path from "node:path";

export function nativePackageInvocations(root: string, platform: string): { command: string[]; baseline: string; report: string }[] {
	return ["0.1.0-draft.1", "0.1.0-draft.2"].flatMap((contract) => ["typescript", "rust"].map((binding) => {
		const prefix = contract === "0.1.0-draft.1" ? "package" : "package-resolution";
		const output = path.join(root, ".dev/out/mck");
		const baseline = path.join(output, `${prefix}-${binding === "typescript" ? "typescript-adapter" : "rust"}.json`);
		const report = path.join(output, `${prefix}-native-${binding}.json`);
		const adapter = binding === "typescript" ? "bun" : path.join(root, "ecosystem/morphir-rust/target/debug", platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust");
		const adapterArgs = [
			...(binding === "typescript" ? [path.join(root, "ecosystem/morphir-typescript/packages/mck/src/adapter.ts")] : []),
			"--suite", "package", "--contract", contract,
		];
		return { baseline, report, command: [
			"cargo", "run", "--locked", "--package", "morphir", "--", "mck", "package", "run",
			"--kit", path.join(root, "spec/package/mck"), "--contract", contract, "--adapter", adapter,
			...adapterArgs.flatMap((arg) => ["--adapter-arg", arg]), "--report", report,
		] };
	}));
}

/** Temporary migration comparison, never a compatibility runner or schema gate. */
export function assertPackageParity(baseline: unknown, native: unknown): void {
	function stable(value: unknown) {
		if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("expected a package report");
		const { driverVersion: _driver, startedAt: _time, ...report } = value as Record<string, unknown>;
		const count = report.contractVersion === "0.1.0-draft.1" ? 80 : report.contractVersion === "0.1.0-draft.2" ? 78 : 0;
		if (report.suite !== "package" || count === 0 || !Array.isArray(report.records) || report.records.length !== count) {
			throw new Error("expected the complete 80-case integrity or 78-case resolution report");
		}
		if (!report.records.every((record) => record !== null && typeof record === "object" && record.result === "pass")) {
			throw new Error("every required package case must pass before migration");
		}
		return report;
	}
	if (!isDeepStrictEqual(stable(baseline), stable(native))) {
		throw new Error("package reports differ beyond driverVersion and startedAt");
	}
}

if (import.meta.main) {
	const args = process.argv.slice(2);
	if (args.length !== 2) {
		console.error("usage: package-mck-parity <typescript-report.json> <native-report.json>");
		process.exit(2);
	}
	try {
		assertPackageParity(...args.map((file) => JSON.parse(readFileSync(file, "utf8"))) as [unknown, unknown]);
		console.log("package migration parity: complete reports match");
	} catch (error) {
		console.error(String(error));
		process.exit(1);
	}
}
