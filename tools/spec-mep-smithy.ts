// Checks the Smithy model of the Morphir Extension Protocol in
// spec/mep/smithy with the moonrockz/smithy CLI.
//
// Usage (from the parent repository root):
//
//   bun run tools/spec-mep-smithy.ts      # or: mise run spec:mep-smithy-check
//
// The check:
//
// 1. validates the model files in spec/mep/smithy/model and checks that
//    they are in `smithy format` form;
// 2. validates each transcript in spec/mep/smithy/transcripts as a session
//    of morphir.mep#MepSession; a transcript with a jsonrpc-expect list
//    passes when its findings match the list;
// 3. checks that every JSON-RPC example in the MEP protocol draft is a
//    message of a transcript, and every other JSON example is a value in
//    spec/mep/smithy/values.json;
// 4. validates each value in values.json against its shape;
// 5. validates the request, result and transport offers of each case in
//    spec/mep/mck/model-transport.cases.json, and compares the findings with
//    spec/mep/smithy/mck-expectations.json;
// 6. compares the types of spec/mep/contract/src/mep.gleam with the shapes
//    of the model: record fields with structure members, by wire name, and
//    enum constructors with enum members. CONTRACT_EXCEPTIONS lists each
//    known difference.
//
// The CLI runs through moonx at a pinned version, so the result does not
// depend on a locally installed smithy binary.
import { spawn } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const SMITHY_CLI = ["moonx", "moonrockz/smithy-cli@0.6.0"] as const;
export const PROTOCOL = "morphir.mep#MepSession";
export const EXTENSION_SERVICE = "morphir.mep#ExtensionService";
export const PROTOCOL_DRAFT = "docs/design/draft/extensions/protocol.md";

export type Fence = { info: string; line: number; body: string };

/** The fenced code blocks of a Markdown document, with the line of each
 * opening fence. Only backtick fences at the start of a line are read. */
export function fences(markdown: string): Fence[] {
	const found: Fence[] = [];
	const lines = markdown.split(/\r?\n/);
	for (let index = 0; index < lines.length; index++) {
		const open = /^(`{3,})(.*)$/.exec(lines[index] ?? "");
		if (!open) continue;
		const [, marker = "", info = ""] = open;
		const body: string[] = [];
		let close = index + 1;
		for (; close < lines.length && !(lines[close] ?? "").startsWith(marker); close++) {
			body.push(lines[close] ?? "");
		}
		found.push({ info: info.trim(), line: index + 1, body: body.join("\n") });
		index = close;
	}
	return found;
}

function parse(text: string): unknown {
	try {
		return JSON.parse(text);
	} catch {
		return undefined;
	}
}

function isMessage(value: unknown): boolean {
	return typeof value === "object" && value !== null && !Array.isArray(value) && "jsonrpc" in value;
}

/** A JSON value as text with object keys sorted, so two values compare equal
 * when they differ only in key order or whitespace. */
export function canonical(value: unknown): string {
	if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
	if (typeof value === "object" && value !== null) {
		const entries = Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
		return `{${entries.map(([key, member]) => `${JSON.stringify(key)}:${canonical(member)}`).join(",")}}`;
	}
	return JSON.stringify(value);
}

export type Example = { line: number; value: unknown };

/** The JSON examples of the protocol draft. A `json` fence is one example.
 * In a `text` fence, such as the Content-Length framing example, each line
 * that is a JSON-RPC message is one example. */
export function protocolExamples(markdown: string): { messages: Example[]; values: Example[] } {
	const messages: Example[] = [];
	const values: Example[] = [];
	for (const fence of fences(markdown)) {
		if (fence.info === "json") {
			const value = parse(fence.body);
			if (value === undefined) throw new Error(`${PROTOCOL_DRAFT}:${fence.line}: the json fence is not JSON`);
			(isMessage(value) ? messages : values).push({ line: fence.line, value });
		} else if (fence.info === "text") {
			fence.body.split("\n").forEach((text, offset) => {
				const value = parse(text);
				if (isMessage(value)) messages.push({ line: fence.line + 1 + offset, value });
			});
		}
	}
	return { messages, values };
}

/** The messages of a Markdown transcript: the bodies of its `jsonrpc A` and
 * `jsonrpc A -> B` fences. */
export function transcriptMessages(markdown: string): unknown[] {
	return fences(markdown)
		.filter((fence) => /^jsonrpc\s/.test(fence.info))
		.map((fence) => parse(fence.body));
}

/** The examples whose value is not in `known`, as protocol draft lines. */
export function uncovered(examples: Example[], known: unknown[]): number[] {
	const keys = new Set(known.map(canonical));
	return examples.filter((example) => !keys.has(canonical(example.value))).map((example) => example.line);
}

/** The value at an RFC 6901 JSON Pointer. */
export function pointerValue(document: unknown, pointer: string): unknown {
	if (pointer === "") return document;
	let current = document;
	for (const raw of pointer.slice(1).split("/")) {
		const key = raw.replaceAll("~1", "/").replaceAll("~0", "~");
		if (typeof current !== "object" || current === null || !(key in current)) {
			throw new Error(`the pointer ${pointer} does not name a value`);
		}
		current = (current as Record<string, unknown>)[key];
	}
	return current;
}

/** The finding codes of a CLI JSON report, sorted. */
export function findingCodes(report: string): string[] {
	const parsed = parse(report) as { findings?: { code: string }[] } | undefined;
	if (!parsed || !Array.isArray(parsed.findings)) throw new Error(`the CLI did not write a JSON report: ${report.trim()}`);
	return parsed.findings.map((finding) => finding.code).sort();
}

/** A difference between expected and actual finding codes, or undefined. */
export function codeDifference(expected: string[], actual: string[]): string | undefined {
	const want = [...expected].sort();
	return canonical(want) === canonical(actual) ? undefined : `expected [${want.join(", ")}], found [${actual.join(", ")}]`;
}

export type GleamType = { name: string; constructors: { name: string; labels: string[] }[] };

/** The `pub type` declarations of a Gleam module, with the labels of each
 * constructor. Comments are removed first. */
export function gleamTypes(source: string): GleamType[] {
	const code = source.replace(/\/\/.*$/gm, "");
	const types: GleamType[] = [];
	for (const match of code.matchAll(/pub type (\w+)\s*\{([^}]*)\}/g)) {
		const [, name = "", body = ""] = match;
		const constructors: GleamType["constructors"] = [];
		let index = 0;
		while (index < body.length) {
			const head = /[A-Z]\w*/.exec(body.slice(index));
			if (!head) break;
			index += head.index + head[0].length;
			const labels: string[] = [];
			if (body.slice(index).trimStart().startsWith("(")) {
				index = body.indexOf("(", index) + 1;
				let depth = 1;
				let part = "";
				const parts: string[] = [];
				for (; depth > 0 && index < body.length; index++) {
					const char = body[index];
					if (char === "(") depth++;
					if (char === ")") depth--;
					if (depth === 1 && char === ",") {
						parts.push(part);
						part = "";
					} else if (depth > 0) part += char;
				}
				parts.push(part);
				for (const argument of parts) {
					const label = /^\s*([a-z]\w*)\s*:/.exec(argument);
					if (label?.[1]) labels.push(label[1]);
				}
			}
			constructors.push({ name: head[0], labels });
		}
		types.push({ name, constructors });
	}
	return types;
}

/** A snake_case Gleam label as a lowerCamelCase wire name. */
export function wireName(label: string): string {
	return label.replace(/_([a-z0-9])/g, (_, letter: string) => letter.toUpperCase());
}

export type ContractException = {
	/** Wire names of Gleam fields that the structure does not have. */
	missing?: string[];
	/** Structure members that the Gleam record does not have. */
	added?: string[];
	/** Labels stay snake_case on the wire. */
	snakeCase?: boolean;
	/** The model has this shape type instead, such as `document`. */
	shapeType?: string;
	/** A sum type that the model writes as one structure with a tag member. */
	tag?: string;
	/** The model writes the constructors as operations of the services. */
	operations?: boolean;
	reason: string;
};

/** The known differences between the Gleam contract and the Smithy model. */
export const CONTRACT_EXCEPTIONS: Record<string, ContractException> = {
	Json: { shapeType: "document", reason: "any JSON value" },
	RequestId: { shapeType: "document", reason: "an untagged number or string (smithy-2qe.34.22)" },
	Method: { operations: true, reason: "each method is an operation" },
	ExtensionInfo: { snakeCase: true, reason: "the wire names stay snake_case" },
	ExtensionCapabilities: { missing: ["extra"], reason: "extra members beside named members (smithy-2qe.34.18)" },
	CompileOptions: { missing: ["extra"], reason: "extra members beside named members (smithy-2qe.34.18)" },
	CapabilityClaimSet: { added: ["statementVersion"], reason: "the draft.1 name of claimsVersion (smithy-2qe.34.21)" },
	CompileModelResult: { tag: "success", reason: "a sum tagged by success (smithy-2qe.34.21)" },
};

type AstShape = { type: string; members?: Record<string, unknown>; operations?: { target: string }[] };

function sorted(values: Iterable<string>): string[] {
	return [...new Set(values)].sort();
}

/** The differences between the Gleam types and the shapes of a Smithy JSON
 * AST in `namespace`. An empty list means that they agree. */
export function contractDifferences(
	types: GleamType[],
	shapes: Record<string, AstShape>,
	namespace: string,
	exceptions: Record<string, ContractException> = CONTRACT_EXCEPTIONS,
): string[] {
	const differences: string[] = [];
	for (const type of types) {
		const exception = exceptions[type.name] ?? { reason: "" };
		const id = `${namespace}#${type.name}`;
		if (exception.operations) {
			const count = Object.values(shapes)
				.filter((shape) => shape.type === "service")
				.reduce((total, shape) => total + (shape.operations?.length ?? 0), 0);
			if (count !== type.constructors.length) {
				differences.push(`${type.name}: ${type.constructors.length} constructors, but the services have ${count} operations`);
			}
			continue;
		}
		const shape = shapes[id];
		if (!shape) {
			differences.push(`${type.name}: the model has no shape ${id}`);
			continue;
		}
		const isRecord = type.constructors.length === 1 && (type.constructors[0]?.labels.length ?? 0) > 0;
		const isEnum = type.constructors.every((constructor) => constructor.labels.length === 0);
		const expectedType = exception.shapeType ?? (isEnum ? "enum" : "structure");
		if (shape.type !== expectedType && !(expectedType === "enum" && shape.type === "intEnum")) {
			differences.push(`${type.name}: expected a ${expectedType}, found a ${shape.type}`);
			continue;
		}
		if (exception.shapeType) continue;
		const members = sorted(Object.keys(shape.members ?? {}));
		if (isEnum) {
			if (members.length !== type.constructors.length) {
				differences.push(`${type.name}: ${type.constructors.length} constructors, but ${members.length} enum members`);
			}
			continue;
		}
		if (!isRecord && !exception.tag) {
			differences.push(`${type.name}: a sum type with no listed mapping`);
			continue;
		}
		const labels = type.constructors.flatMap((constructor) => constructor.labels);
		const fields = labels.map((label) => (exception.snakeCase ? label : wireName(label)));
		const expected = sorted([...fields, ...(exception.tag ? [exception.tag] : []), ...(exception.added ?? [])]).filter(
			(field) => !(exception.missing ?? []).includes(field),
		);
		const absent = expected.filter((field) => !members.includes(field));
		const extra = members.filter((member) => !expected.includes(member));
		if (absent.length > 0) differences.push(`${type.name}: the structure has no member ${absent.join(", ")}`);
		if (extra.length > 0) differences.push(`${type.name}: the contract has no field ${extra.join(", ")}`);
	}
	return differences;
}

type Run = { status: number | null; stdout: string; stderr: string };

function smithy(args: string[], input?: string): Promise<Run> {
	return new Promise((resolve, reject) => {
		const child = spawn(SMITHY_CLI[0], [...SMITHY_CLI.slice(1), ...args], { stdio: "pipe" });
		let stdout = "";
		let stderr = "";
		child.stdout.on("data", (chunk: Buffer) => (stdout += chunk));
		child.stderr.on("data", (chunk: Buffer) => (stderr += chunk));
		child.on("error", reject);
		child.on("close", (status) => resolve({ status, stdout, stderr }));
		child.stdin.end(input ?? "");
	});
}

async function inParallel<T>(items: T[], limit: number, work: (item: T) => Promise<void>): Promise<void> {
	let next = 0;
	const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
		while (next < items.length) await work(items[next++] as T);
	});
	await Promise.all(workers);
}

type ValueEntry = {
	name: string;
	shape: string;
	source: string;
	value?: unknown;
	pointer?: string;
	expect: string[];
};

type CaseExpectation = { request: string[]; result?: string[]; note: string };

type McCase = {
	id: string;
	request: { id: unknown };
	result?: unknown;
	hostOffer?: { modelTransport?: unknown };
	guestSupport?: { modelTransport?: unknown };
};

async function main(): Promise<void> {
	const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
	const smithyDir = path.join(root, "spec/mep/smithy");
	const read = (relative: string) => readFileSync(path.join(root, relative), "utf8");
	const models = readdirSync(path.join(smithyDir, "model"))
		.filter((name) => name.endsWith(".smithy"))
		.sort()
		.map((name) => path.join(smithyDir, "model", name));
	const failures: string[] = [];
	let checks = 0;
	const check = (failure: string | undefined) => {
		checks++;
		if (failure) failures.push(failure);
	};

	const model = await smithy(["validate", ...models]);
	check(model.status === 0 ? undefined : `model: ${model.stdout}${model.stderr}`.trim());
	const format = await smithy(["format", "--check", ...models]);
	check(format.status === 0 ? undefined : `model format: run smithy format --write on the model files.\n${format.stdout}${format.stderr}`.trim());
	if (failures.length > 0) {
		console.error(failures.join("\n"));
		process.exit(1);
	}

	const transcripts = readdirSync(path.join(smithyDir, "transcripts"))
		.filter((name) => name.endsWith(".md"))
		.sort();
	const transcriptBodies: unknown[] = [];
	await inParallel(transcripts, 8, async (name) => {
		const file = path.join(smithyDir, "transcripts", name);
		transcriptBodies.push(...transcriptMessages(readFileSync(file, "utf8")));
		const run = await smithy(["validate", "rpc", "transcript", "--protocol", PROTOCOL, ...models, file]);
		check(run.status === 0 ? undefined : `transcripts/${name}:\n${run.stdout}${run.stderr}`.trim());
	});

	const examples = protocolExamples(read(PROTOCOL_DRAFT));
	const values = (JSON.parse(read("spec/mep/smithy/values.json")) as { values: ValueEntry[] }).values;
	for (const line of uncovered(examples.messages, transcriptBodies)) {
		check(`${PROTOCOL_DRAFT}:${line}: the JSON-RPC example is not a message of a transcript`);
	}
	const draftValues = values.filter((entry) => entry.source === PROTOCOL_DRAFT).map((entry) => entry.value);
	for (const line of uncovered(examples.values, draftValues)) {
		check(`${PROTOCOL_DRAFT}:${line}: the JSON example is not in values.json`);
	}

	await inParallel(values, 8, async (entry) => {
		const value = entry.pointer === undefined ? entry.value : pointerValue(JSON.parse(read(entry.source)), entry.pointer);
		const run = await smithy(
			["validate", "value", "--shape", entry.shape, "--value", "-", "--diagnostics", "json", ...models],
			JSON.stringify(value),
		);
		const difference = codeDifference(entry.expect, findingCodes(run.stdout));
		check(difference && `values.json "${entry.name}": ${difference}`);
	});

	const corpus = JSON.parse(read("spec/mep/mck/model-transport.cases.json")) as { cases: McCase[] };
	const expected = (JSON.parse(read("spec/mep/smithy/mck-expectations.json")) as {
		cases: Record<string, CaseExpectation>;
	}).cases;
	const ids = new Set(corpus.cases.map((entry) => entry.id));
	const scratch = mkdtempSync(path.join(tmpdir(), "mep-smithy-"));
	for (const id of Object.keys(expected)) check(ids.has(id) ? undefined : `mck-expectations.json: ${id} is not an MCK case`);
	await inParallel(corpus.cases, 8, async (entry) => {
		const expectation = expected[entry.id];
		if (!expectation) return check(`mck-expectations.json: no expectation for ${entry.id}`);
		const request = JSON.stringify(entry.request);
		const rpc = ["validate", "rpc", "--version", "2.0", "--service", EXTENSION_SERVICE, "--diagnostics", "json"];
		const message = await smithy([...rpc, "--message", "-", ...models], request);
		const requestDifference = codeDifference(expectation.request, findingCodes(message.stdout));
		check(requestDifference && `${entry.id} request: ${requestDifference}`);
		if ((entry.result === undefined) !== (expectation.result === undefined)) {
			return check(`${entry.id}: the case and mck-expectations.json disagree about a result`);
		}
		if (entry.result !== undefined && expectation.result !== undefined) {
			const response = JSON.stringify({ jsonrpc: "2.0", id: entry.request.id, result: entry.result });
			// The CLI reads only one input from stdin, so the original request
			// is a file.
			const original = path.join(scratch, `${entry.id}.request.json`);
			writeFileSync(original, request);
			const reply = await smithy([...rpc, "--response", "-", "--request", original, ...models], response);
			const resultDifference = codeDifference(expectation.result, findingCodes(reply.stdout));
			check(resultDifference && `${entry.id} result: ${resultDifference}`);
		}
		for (const [side, offer] of [
			["hostOffer", entry.hostOffer?.modelTransport],
			["guestSupport", entry.guestSupport?.modelTransport],
		] as const) {
			if (offer === undefined) continue;
			const run = await smithy(
				["validate", "value", "--shape", "morphir.mep#ModelTransportSupport", "--value", "-", "--diagnostics", "json", ...models],
				JSON.stringify(offer),
			);
			const difference = codeDifference([], findingCodes(run.stdout));
			check(difference && `${entry.id} ${side}.modelTransport: ${difference}`);
		}
	});

	rmSync(scratch, { recursive: true, force: true });

	const ast = await smithy(["ast", ...models]);
	const shapes = (JSON.parse(ast.stdout) as { shapes: Record<string, AstShape> }).shapes;
	const differences = contractDifferences(gleamTypes(read("spec/mep/contract/src/mep.gleam")), shapes, "morphir.mep");
	check(differences.length === 0 ? undefined : `mep.gleam and the Smithy model differ:\n  ${differences.join("\n  ")}`);

	if (failures.length > 0) {
		console.error(failures.join("\n\n"));
		console.error(`\n${failures.length} of ${checks} MEP Smithy checks failed.`);
		process.exit(1);
	}
	console.log(
		`MEP Smithy model: ${checks} checks passed (${transcripts.length} transcripts, ${examples.messages.length} protocol messages, ${values.length} values, ${corpus.cases.length} MCK cases).`,
	);
}

if (import.meta.main) await main();
