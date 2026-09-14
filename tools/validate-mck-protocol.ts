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
// Every message is also validated against the root schema, with no
// --entrypoint: the root oneOf is what an adapter author reads a raw line
// against, so a message that only validates at its entrypoint would leave the
// root wrong (a shape matching two root branches at once, for instance).
//
// Both contract files here are copies of the originals in the morphir-typescript
// submodule. This checker byte-compares them when the submodule is checked out,
// which is what keeps them from drifting; when it is absent the comparison
// prints a note and is skipped.
//
// --example overrides the default spec/ir/mck/protocol.example.json, so this
// checker's request/response matching can be exercised against a fixture with
// a deliberately wrong or missing response id (see the manual verification
// recorded in the task report; there is no test runner for tools/ in this
// repository).
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

// ------------------------------------------------- the contract copies

/** The submodule directory holding the originals of both contract files. */
const submoduleDir = path.join(
	repositoryRoot,
	"ecosystem",
	"morphir-typescript",
	"packages",
	"mck",
);

/** Copies that must match the submodule byte for byte, by file name. */
const CONTRACT_FILES: readonly string[] = [
	"protocol.schema.json",
	"protocol.example.json",
];

/** Byte-compares the contract copies with the submodule originals. Returns the failures. */
function contractDrift(): string[] {
	const original = path.join(submoduleDir, "protocol.schema.json");
	if (!existsSync(original)) {
		console.log(
			`contract copies: skipped (${path.relative(repositoryRoot, original)} not checked out)`,
		);
		return [];
	}
	const drift: string[] = [];
	for (const name of CONTRACT_FILES) {
		const here = path.join(repositoryRoot, "spec", "ir", "mck", name);
		const there = path.join(submoduleDir, name);
		if (!existsSync(there)) {
			drift.push(`${name}: the submodule original is missing`);
			continue;
		}
		if (readFileSync(here).equals(readFileSync(there))) {
			console.log(`contract copy ${name}: ok (identical to the submodule)`);
		} else {
			drift.push(
				`${name}: differs from ${path.relative(repositoryRoot, there)}; re-copy it`,
			);
		}
	}
	return drift;
}

const driftErrors = contractDrift();
for (const message of driftErrors) console.log(`FAIL ${message}`);

// ------------------------------------------------- the example messages

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

/** A message is only readable as a protocol message when it is a JSON object. */
function isMessage(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

function describe(v: unknown): string {
	if (v === null) return "null";
	if (Array.isArray(v)) return "an array";
	if (v === undefined) return "absent";
	return `a ${typeof v}`;
}

for (const [index, entry] of entries.entries()) {
	if (entry.direction === "request") {
		if (pending !== null && !pending.answered) {
			sequenceErrors.push(
				`request id ${String(pending.id)} (${pending.op}) has no response`,
			);
		}
		if (!isMessage(entry.message)) {
			sequenceErrors.push(
				`entry ${index}: "message" is ${describe(entry.message)}, not an object`,
			);
			pending = null;
			continue;
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
		if (!isMessage(entry.message)) {
			sequenceErrors.push(
				`entry ${index}: "message" is ${describe(entry.message)}, not an object`,
			);
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

/** One run of the jsonschema CLI over a directory, as `file name -> passed`. */
interface Verdicts {
	readonly byFile: ReadonlyMap<string, boolean>;
	readonly output: string;
}

/** Validates a directory of instances at one entry point; `""` is the root schema. */
function validateDirectory(directory: string, pointer: string): Verdicts {
	const args = ["validate", schemaPath, directory, "--verbose", "--continue"];
	if (pointer !== "") args.push("--entrypoint", pointer);
	const run = Bun.spawnSync(["jsonschema", ...args], { cwd: repositoryRoot });
	const output = `${run.stdout.toString()}\n${run.stderr.toString()}`;
	const byFile = new Map<string, boolean>();
	for (const line of output.split(/\r?\n/)) {
		const match = line.match(/^(ok|fail):\s+(.*)$/);
		const verdict = match?.[1];
		const file = match?.[2];
		if (verdict === undefined || file === undefined) continue;
		byFile.set(path.basename(file.trim()), verdict === "ok");
	}
	return { byFile, output };
}

const workspace = mkdtempSync(path.join(os.tmpdir(), "mck-protocol-"));
let schemaFailed = 0;
try {
	// The root schema sees every message at once; each entrypoint group sees
	// only the messages that belong to it.
	const rootDirectory = path.join(workspace, "root");
	mkdirSync(rootDirectory, { recursive: true });
	for (const instance of instances) {
		writeFileSync(
			path.join(rootDirectory, `${instance.index}.json`),
			JSON.stringify(instance.message),
		);
	}
	const root = validateDirectory(rootDirectory, "");

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
		const { byFile, output } = validateDirectory(directory, pointer);
		for (const [name, instance] of files) {
			const accepted = byFile.get(name);
			const atRoot = root.byFile.get(name);
			const label = `entry ${instance.index} (${instance.direction}, ${pointer})`;
			if (accepted === true && atRoot === true) {
				console.log(`${label}: ok (and at the root schema)`);
				continue;
			}
			schemaFailed += 1;
			if (accepted !== true) {
				console.log(`${label}: FAIL${accepted === undefined ? " (no verdict)" : ""}`);
				console.log(output.trim());
			} else {
				console.log(
					`${label}: FAIL at the root schema${atRoot === undefined ? " (no verdict)" : ""}`,
				);
				console.log(root.output.trim());
			}
		}
	}
} finally {
	rmSync(workspace, { recursive: true, force: true });
}

// Every entry is either schema-checked (ok or failed) or dropped before the
// schema ever saw it by a sequence error, so the three counts add up to the
// number of entries in the example. Sequence and contract errors are counted
// on their own line, because one of them can name a request rather than an
// entry.
const unchecked = entries.length - instances.length;
const otherErrors = sequenceErrors.length + driftErrors.length;
console.log(
	`\n${instances.length - schemaFailed} ok, ${schemaFailed} failed, ${unchecked} not schema-checked out of ${entries.length} example entries`,
);
console.log(`${otherErrors} sequence or contract error(s)`);
if (schemaFailed + otherErrors > 0) process.exit(1);
