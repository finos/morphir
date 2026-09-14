// Validates every message in the Morphir Compatibility Kit's adapter protocol
// example against the protocol schema, so the two contract copies cannot drift.
//
//   bun run tools/validate-mck-protocol.ts [--example <file>]
//
// protocol.example.json is an array of { direction, message } entries recorded
// in exchange order. A "request" message validates against
// #/definitions/Request and becomes the pending request. A "response" message
// must answer the pending request by id: it validates against the definition
// matching the pending request's op (capabilities against
// #/definitions/Capabilities, decode and readTree against
// #/definitions/DecodeResponse, writeTree against
// #/definitions/WriteTreeResponse), and its `id` must equal the pending
// request's `id`. A request may be followed by more than one response (the
// example illustrates decode's success and failure shapes back to back for
// the same request id); each still validates against the pending request's
// op and id. exit has no response. A request left with no response at all by
// the time the next request arrives, or at the end of the file, is an error
// (exit is exempt), as is a response with no preceding request, an id
// mismatch, or a direction other than request or response.
//
// --example overrides the default spec/ir/mck/protocol.example.json, so this
// checker's request/response matching can be exercised against a fixture with
// a deliberately wrong or missing response id (see the manual verification
// recorded in the task report; there is no test runner for tools/ in this
// repository).
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

const exampleFlagIndex = process.argv.indexOf("--example");
const examplePath =
	exampleFlagIndex !== -1 && process.argv[exampleFlagIndex + 1] !== undefined
		? path.resolve(process.argv[exampleFlagIndex + 1] as string)
		: path.join(repositoryRoot, "spec", "ir", "mck", "protocol.example.json");

interface ExampleEntry {
	readonly direction: string;
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

/** The request currently awaiting at least one response, matched strictly by id. */
interface Pending {
	readonly index: number;
	readonly id: unknown;
	readonly op: string;
	answered: boolean;
}

const instances: Instance[] = [];
const sequenceErrors: string[] = [];
let pending: Pending | null = null;

for (const [index, entry] of entries.entries()) {
	if (entry.direction === "request") {
		if (pending !== null && !pending.answered) {
			sequenceErrors.push(
				`request id ${String(pending.id)} (${pending.op}) has no response`,
			);
		}
		const id = entry.message.id;
		const op = entry.message.op;
		instances.push({
			index,
			direction: "request",
			pointer: "#/definitions/Request",
			message: entry.message,
		});
		pending =
			typeof op === "string" && op !== "exit"
				? { index, id, op, answered: false }
				: null;
		continue;
	}

	if (entry.direction === "response") {
		if (pending === null) {
			sequenceErrors.push(`entry ${index}: response without a preceding request`);
			continue;
		}
		const id = entry.message.id;
		if (typeof id !== "number" || !Number.isInteger(id) || id !== pending.id) {
			sequenceErrors.push(
				`response id ${String(id)} does not answer the pending request id ${String(pending.id)}`,
			);
			continue;
		}
		const pointer = RESPONSE_POINTERS.get(pending.op);
		if (pointer === undefined) {
			sequenceErrors.push(
				`entry ${index}: answers unknown op "${pending.op}"`,
			);
			continue;
		}
		instances.push({
			index,
			direction: "response",
			pointer,
			message: entry.message,
		});
		pending.answered = true;
		continue;
	}

	sequenceErrors.push(
		`entry ${index}: unknown direction "${String(entry.direction)}" (expected "request" or "response")`,
	);
}

if (pending !== null && !pending.answered) {
	sequenceErrors.push(
		`request id ${String(pending.id)} (${pending.op}) has no response`,
	);
}

for (const message of sequenceErrors) console.log(`FAIL ${message}`);

const workspace = mkdtempSync(path.join(os.tmpdir(), "mck-protocol-"));
let schemaFailed = 0;
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
				schemaFailed += 1;
				console.log(`${label}: FAIL${accepted === undefined ? " (no verdict)" : ""}`);
				console.log(output.trim());
			}
		}
	}
} finally {
	rmSync(workspace, { recursive: true, force: true });
}

const failed = sequenceErrors.length + schemaFailed;
console.log(
	`\n${instances.length - schemaFailed} ok, ${failed} failed out of ${instances.length} protocol messages`,
);
if (failed > 0) process.exit(1);
