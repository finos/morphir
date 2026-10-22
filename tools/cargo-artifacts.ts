type CargoMessage = {
	reason?: string;
	target?: { name?: string; kind?: string[] };
	executable?: string | null;
};

/** Select an executable from Cargo's actual compiler-artifact messages. */
export function builtExecutable(
	messages: string,
	selector: { name: string; kind: "bin" | "test" } = { name: "morphir", kind: "bin" },
): string {
	let executable: string | undefined;
	for (const line of messages.split(/\r?\n/)) {
		let message: CargoMessage;
		try {
			message = JSON.parse(line) as CargoMessage;
		} catch {
			continue;
		}
		if (
			message !== null &&
			typeof message === "object" &&
			message.reason === "compiler-artifact" &&
			message.target?.name === selector.name &&
			Array.isArray(message.target.kind) &&
			message.target.kind.includes(selector.kind) &&
			typeof message.executable === "string" &&
			message.executable.length > 0
		) {
			if (executable !== undefined && executable !== message.executable) {
				throw new Error(`cargo reported multiple ${selector.name} ${selector.kind} executables`);
			}
			executable = message.executable;
		}
	}
	if (executable === undefined) {
		throw new Error(`cargo reported no ${selector.name} ${selector.kind === "bin" ? "binary" : "test executable"}`);
	}
	return executable;
}
