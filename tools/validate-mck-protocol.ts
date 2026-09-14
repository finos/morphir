// Validates every message in the Morphir Compatibility Kit's adapter protocol
// example against the protocol schema, so the two contract copies cannot drift.
//
//   bun run tools/validate-mck-protocol.ts
//
// protocol.example.json is an array of { direction, message } entries recorded
// in exchange order. A "request" message validates against
// #/definitions/Request. A "response" message validates against the
// definition matching the request it answers: capabilities against
// #/definitions/Capabilities, decode and readTree against
// #/definitions/DecodeResponse, writeTree against
// #/definitions/WriteTreeResponse. exit has no response.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const schemaPath = path.join(
	repositoryRoot,
	"spec",
	"ir",
	"mck",
	"protocol.schema.json",
);
const examplePath = path.join(
	repositoryRoot,
	"spec",
	"ir",
	"mck",
	"protocol.example.json",
);

interface ExampleEntry {
	readonly direction: "request" | "response";
	readonly message: Record<string, unknown>;
}

interface Instance {
	readonly index: number;
	readonly direction: "request" | "response";
	readonly pointer: string;
	readonly message: Record<string, unknown>;
}

/** Maps a request op to the definition its response validates against. */
const RESPONSE_POINTERS: ReadonlyMap<string, string> = new Map([
	["capabilities", "#/definitions/Capabilities"],
	["decode", "#/definitions/DecodeResponse"],
	["readTree", "#/definitions/DecodeResponse"],
	["writeTree", "#/definitions/WriteTreeResponse"],
]);

const raw = await Bun.file(examplePath).json();
if (!Array.isArray(raw)) {
	console.error(`error: ${examplePath} must be a JSON array`);
	process.exit(1);
}
const entries = raw as ExampleEntry[];

const instances: Instance[] = [];
let lastOp: string | undefined;
for (const [index, entry] of entries.entries()) {
	if (entry.direction === "request") {
		const op = entry.message.op;
		lastOp = typeof op === "string" ? op : undefined;
		instances.push({
			index,
			direction: "request",
			pointer: "#/definitions/Request",
			message: entry.message,
		});
		continue;
	}
	if (lastOp === "exit" || lastOp === undefined) {
		console.error(
			`error: entry ${index} is a response with no matching request op`,
		);
		process.exit(1);
	}
	const pointer = RESPONSE_POINTERS.get(lastOp);
	if (pointer === undefined) {
		console.error(`error: entry ${index} answers unknown op "${lastOp}"`);
		process.exit(1);
	}
	instances.push({
		index,
		direction: "response",
		pointer,
		message: entry.message,
	});
}

const workspace = mkdtempSync(path.join(os.tmpdir(), "mck-protocol-"));
let failed = 0;
try {
	const byPointer = new Map<string, Instance[]>();
	for (const instance of instances) {
		const group = byPointer.get(instance.pointer) ?? [];
		group.push(instance);
		byPointer.set(instance.pointer, group);
	}

	for (const [pointer, group] of byPointer) {
		const directory = path.join(workspace, pointer.replace(/[^\w]+/g, "_"));
		mkdirSync(directory, { recursive: true });
		const files = new Map<string, Instance>();
		for (const instance of group) {
			const name = `${instance.index}.json`;
			writeFileSync(
				path.join(directory, name),
				JSON.stringify(instance.message),
			);
			files.set(name, instance);
		}
		const run = Bun.spawnSync(
			[
				"jsonschema",
				"validate",
				schemaPath,
				directory,
				"--verbose",
				"--continue",
				"--entrypoint",
				pointer,
			],
			{ cwd: repositoryRoot },
		);
		const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
		const verdicts = new Map<string, boolean>();
		for (const line of output.split(/\r?\n/)) {
			const match = line.match(/^(ok|fail):\s+(.*)$/);
			const verdict = match?.[1];
			const file = match?.[2];
			if (verdict === undefined || file === undefined) continue;
			verdicts.set(path.basename(file.trim()), verdict === "ok");
		}
		for (const [name, instance] of files) {
			const accepted = verdicts.get(name);
			const label = `entry ${instance.index} (${instance.direction}, ${pointer})`;
			if (accepted === true) {
				console.log(`${label}: ok`);
			} else {
				failed += 1;
				console.log(`${label}: FAIL${accepted === undefined ? " (no verdict)" : ""}`);
				console.log(output.trim());
			}
		}
	}
} finally {
	rmSync(workspace, { recursive: true, force: true });
}

console.log(
	`\n${instances.length - failed} ok, ${failed} failed out of ${instances.length} protocol messages`,
);
if (failed > 0) process.exit(1);
