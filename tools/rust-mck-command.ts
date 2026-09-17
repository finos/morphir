import path from "node:path";

/** Resolve the Rust adapter and select an existing shared MCK CLI command. */
export function rustMckInvocation(root: string, platform: string, args: readonly string[]): {
	adapter: string;
	command: string[];
} {
	const suite = args[0] === "--suite" ? args[1] : "ir";
	if (suite !== "ir" && suite !== "package") {
		throw new Error("expected --suite ir or --suite package");
	}
	const forwarded = args[0] === "--suite" ? args.slice(2) : args;
	if (forwarded.some((arg) => arg === "--suite" || arg.startsWith("--suite="))) {
		throw new Error("select the suite once, before driver arguments: --suite ir|package");
	}
	if (forwarded.some((arg) => arg === "--adapter" || arg.startsWith("--adapter="))) {
		throw new Error("this wrapper supplies --adapter; run the driver directly to select another adapter");
	}
	if (forwarded.some((arg) => arg.startsWith("--contract="))) {
		throw new Error("select the package contract as --contract <version>");
	}
	const contractPositions = forwarded.flatMap((arg, index) => arg === "--contract" ? [index] : []);
	if (contractPositions.length > 1) {
		throw new Error("select the package contract once");
	}
	const contractPosition = contractPositions[0];
	const contract = contractPosition === undefined ? undefined : forwarded[contractPosition + 1];
	if (contractPosition !== undefined && (contract === undefined || contract.length === 0 || contract.startsWith("--"))) {
		throw new Error("--contract requires a version");
	}
	if (contract !== undefined && suite !== "package") {
		throw new Error("--contract requires --suite package");
	}
	const adapter = path.join(root, "ecosystem/morphir-rust/target/debug",
		platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust");
	const driver = path.join(root, "ecosystem/morphir-typescript/packages/mck/src/cli.ts");
	return {
		adapter,
		command: ["bun", driver, ...(suite === "package" ? ["package", "run"] : ["run"]),
			"--adapter", adapter,
			...(suite === "package" ? ["--adapter-arg", "--suite", "--adapter-arg", "package"] : []),
			...(contract === undefined ? [] : ["--adapter-arg", "--contract", "--adapter-arg", contract]),
			...forwarded],
	};
}
