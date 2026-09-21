import path from "node:path";

/** Resolve the Rust adapter for the retained TypeScript package runner. */
export function rustMckInvocation(root: string, platform: string, args: readonly string[]): {
	adapter: string;
	command: string[];
} {
	if (args[0] !== "--suite" || args[1] !== "package") {
		throw new Error("use --suite package; IR runs moved to morphir mck run --adapter <executable>");
	}
	const forwarded = args.slice(2);
	if (forwarded.some((arg) => arg === "--suite" || arg.startsWith("--suite="))) {
		throw new Error("select the suite once, before driver arguments: --suite package");
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
	if (forwarded.some((arg) => arg.startsWith("--record="))) {
		throw new Error("name the transcript as --record <file>");
	}
	const recordPositions = forwarded.flatMap((arg, index) => arg === "--record" ? [index] : []);
	if (recordPositions.length > 1) {
		throw new Error("record one transcript");
	}
	const recordPosition = recordPositions[0];
	const transcript = recordPosition === undefined ? undefined : forwarded[recordPosition + 1];
	if (recordPosition !== undefined && (transcript === undefined || transcript.length === 0 || transcript.startsWith("--"))) {
		throw new Error("--record requires a transcript file");
	}
	const contractPosition = contractPositions[0];
	const contract = contractPosition === undefined ? undefined : forwarded[contractPosition + 1];
	if (contractPosition !== undefined && (contract === undefined || contract.length === 0 || contract.startsWith("--"))) {
		throw new Error("--contract requires a version");
	}
	const adapter = path.join(root, "ecosystem/morphir-rust/target/debug",
		platform === "win32" ? "mck-adapter-rust.exe" : "mck-adapter-rust");
	const driver = path.join(root, "ecosystem/morphir-typescript/packages/mck/src/cli.ts");
	// The adapter's own arguments follow it, whether the driver spawns it
	// directly or spawns the recording proxy that spawns it.
	const adapterArgs = [
		"--suite", "package",
		...(contract === undefined ? [] : ["--contract", contract]),
	];
	const spawned = transcript === undefined
		? [adapter, ...adapterArgs]
		: [path.join(root, "tools/record-mck-transcript.ts"), transcript, adapter, ...adapterArgs];
	const driverArgs = recordPosition === undefined
		? forwarded
		: [...forwarded.slice(0, recordPosition), ...forwarded.slice(recordPosition + 2)];
	const [program, ...passed] = transcript === undefined ? spawned : ["bun", ...spawned];
	return {
		adapter,
		command: ["bun", driver, "package", "run",
			"--adapter", program as string,
			...passed.flatMap((arg) => ["--adapter-arg", arg]),
			...driverArgs],
	};
}
