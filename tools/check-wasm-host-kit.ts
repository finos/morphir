// Checks the WASM host qualification kit in spec/mep/mck/wasm-host.cases.json
// against the execution profile contract in
// spec/mep/wasm-execution-profiles.json, the contract's document
// spec/mep/wasm-execution-profiles.md, and the profile and qualification
// specs.
//
// Usage (from the parent repository root):
//
//   bun run tools/check-wasm-host-kit.ts           # or: mise run spec:mep-wasm-check
//   bun run tools/check-wasm-host-kit.ts --write   # reassemble .wasm files, refresh digests
//
// The check fails when:
//
// 1. a built .wasm differs from a fresh assembly of its .wat, or its recorded
//    sha256 differs from the file, or a module file is missing;
// 2. a fixture has no leading `;;` comment, or its `;; Cases:` line does not
//    name exactly the cases that use it;
// 3. an element of the contract (a refusal code, fault kind, host outcome,
//    handle result, profile status, notification or memory rule,
//    classification rule, bound, policy entry, host-session or worker rule,
//    known deviation or import) has no case and is not listed in the kit's
//    withoutCase with a reason, or is listed there although a case covers it;
// 4. a case names a requirement or scenario that the specs lack, claims a
//    contract element that does not exist, or claims a refusal or fault that
//    none of its expectations shows;
// 5. a case's appliesTo does not follow from its module's profile, or a case
//    lacks the --abi the worker requires;
// 6. a module meant to load imports something outside the contract's import
//    table, or with another signature, or lacks `handle () -> i32`;
// 7. a timing range does not follow from the contract's call deadlines;
// 8. the document does not state an import, code, bound value, policy value or
//    worker argument of the contract.
//
// The check reads and assembles modules. It never runs one, and it never
// writes an expectation.
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import wabtInit from "wabt";

export const KIT = "spec/mep/mck/wasm-host.cases.json";
export const KIT_DIR = "spec/mep/mck";
export const FIXTURES = "spec/mep/mck/fixtures/wasm";
export const CONTRACT = "spec/mep/wasm-execution-profiles.json";
export const DOCUMENT = "spec/mep/wasm-execution-profiles.md";
export const PROFILE_SPEC = "mep/wasm-execution-profiles/spec.md";
export const QUALIFICATION_SPEC = "mck/wasm-host-qualification/spec.md";

/** Features that wabt needs to assemble the refusal fixtures. Enabling them
 * does not change the encoding of an MVP module. */
export const FEATURES = { threads: true, memory64: true, multi_memory: true };

export type Signature = { params: string[]; results: string[] };

/** WASI preview 1 signatures, from the witx definitions, of the functions the
 * corpus imports. The contract accepts WASI preview 1 "with its standard
 * types" but lists no table, so the kit keeps this one. */
export const WASI_PREVIEW1: Record<string, Signature> = {
	args_sizes_get: { params: ["i32", "i32"], results: ["i32"] },
	environ_sizes_get: { params: ["i32", "i32"], results: ["i32"] },
	clock_time_get: { params: ["i32", "i64", "i32"], results: ["i32"] },
	fd_prestat_get: { params: ["i32", "i32"], results: ["i32"] },
	fd_read: { params: ["i32", "i32", "i32", "i32"], results: ["i32"] },
	fd_write: { params: ["i32", "i32", "i32", "i32"], results: ["i32"] },
	path_open: { params: ["i32", "i32", "i32", "i32", "i32", "i64", "i64", "i32", "i32"], results: ["i32"] },
	poll_oneoff: { params: ["i32", "i32", "i32", "i32"], results: ["i32"] },
	proc_exit: { params: ["i32"], results: [] },
	random_get: { params: ["i32", "i32"], results: ["i32"] },
};

export type Import = { module: string; name: string; kind: string; signature?: Signature };
export type Memory = { min: number; max?: number; shared: boolean; memory64: boolean };
export type Export = { name: string; kind: string; signature?: Signature };
export type ModuleShape = { imports: Import[]; memories: Memory[]; exports: Export[] };

const VALTYPES: Record<number, string> = { 0x7f: "i32", 0x7e: "i64", 0x7d: "f32", 0x7c: "f64", 0x7b: "v128", 0x70: "funcref", 0x6f: "externref" };
const KINDS = ["func", "table", "memory", "global"];

/** The imports, memories and exports of a WASM binary, with the signature of
 * each imported and exported function. Reads sections 1, 2, 3, 5 and 7. */
export function readModule(bytes: Uint8Array): ModuleShape {
	let at = 8;
	const byte = () => {
		if (at >= bytes.length) throw new Error("the module ends early");
		return bytes[at++] as number;
	};
	const leb = () => {
		let value = 0;
		let scale = 1;
		for (;;) {
			const next = byte();
			value += (next & 0x7f) * scale;
			scale *= 128;
			if ((next & 0x80) === 0) return value;
		}
	};
	const vec = <T>(item: () => T) => Array.from({ length: leb() }, item);
	const name = () => {
		const size = leb();
		const text = new TextDecoder().decode(bytes.subarray(at, at + size));
		at += size;
		return text;
	};
	const valtype = () => VALTYPES[byte()] ?? "unknown";
	const limits = (): Memory => {
		const flags = byte();
		const min = leb();
		const max = flags & 1 ? leb() : undefined;
		return { min, ...(max === undefined ? {} : { max }), shared: (flags & 2) !== 0, memory64: (flags & 4) !== 0 };
	};
	if (readU32(bytes, 0) !== 0x6d736100) throw new Error("not a WASM binary");
	const types: Signature[] = [];
	const functions: number[] = [];
	const shape: ModuleShape = { imports: [], memories: [], exports: [] };
	while (at < bytes.length) {
		const id = byte();
		const size = leb();
		const end = at + size;
		if (id === 1) {
			types.push(
				...vec(() => {
					if (byte() !== 0x60) throw new Error("a type that is not a function type");
					return { params: vec(valtype), results: vec(valtype) };
				}),
			);
		} else if (id === 2) {
			for (let count = leb(); count > 0; count--) {
				const imported: Import = { module: name(), name: name(), kind: "" };
				const kind = KINDS[byte()] ?? "unknown";
				imported.kind = kind;
				if (kind === "func") {
					const index = leb();
					functions.push(index);
					imported.signature = types[index];
				} else if (kind === "table") {
					byte();
					limits();
				} else if (kind === "memory") {
					shape.memories.push(limits());
				} else {
					byte();
					byte();
				}
				shape.imports.push(imported);
			}
		} else if (id === 3) {
			functions.push(...vec(leb));
		} else if (id === 5) {
			shape.memories.push(...vec(limits));
		} else if (id === 7) {
			for (const entry of vec(() => ({ name: name(), kind: byte(), index: leb() }))) {
				const kind = KINDS[entry.kind] ?? "unknown";
				const typeIndex = functions[entry.index];
				const signature = kind === "func" && typeIndex !== undefined ? types[typeIndex] : undefined;
				shape.exports.push({ name: entry.name, kind, ...(signature ? { signature } : {}) });
			}
		}
		at = end;
	}
	return shape;
}

function readU32(bytes: Uint8Array, at: number): number {
	return ((bytes[at] ?? 0) | ((bytes[at + 1] ?? 0) << 8) | ((bytes[at + 2] ?? 0) << 16) | ((bytes[at + 3] ?? 0) << 24)) >>> 0;
}

export const signatureText = (signature: Signature | undefined) =>
	signature ? `(${signature.params.join(", ")}) -> ${signature.results.length ? signature.results.join(", ") : "()"}` : "(none)";

const sameSignature = (a: Signature | undefined, b: Signature | undefined) => signatureText(a) === signatureText(b);

export type Rule = { id: string; rule: string };
export type ContractImport = Signature & { module: string; name: string };
export type Profile = {
	status: string;
	namespaces: string[];
	imports: ContractImport[];
	wasi: string | false;
	notifications: Rule[];
	memory?: Rule[];
	callDeadlineSeconds: number;
	handleResults: { result: string }[];
	notificationAdvertisement?: { provisional: boolean; illustrativeMember: string };
};
export type WorkerArgument = { name: string; required?: boolean; flag?: boolean; default?: number | Record<string, number> };
export type Contract = {
	contract: string;
	version: string;
	handleExport: Signature & { name: string };
	statuses: Record<string, string>;
	profiles: Record<string, Profile>;
	classification: { rules: Rule[]; defaultProfile: string };
	bounds: {
		memoryCeilingBytes: number;
		kernelMemoryCeilingBytes: number;
		instructionBudget: Record<string, number>;
		requiredForQualification: string[];
		optionalForQualification: string[];
	};
	memory: Rule[];
	policy: Record<string, unknown>;
	refusals: { code: string }[];
	faults: { kind: string; hostCode?: string; hostOutcome?: string }[];
	hostSession: { frameLimits: { requestBytes: number; responseBytes: number }; rules: (Rule & { code?: string })[] };
	worker: {
		arguments: WorkerArgument[];
		startedBounds: { members: string[]; notEnforcedReasons: string[] };
		refusals: { code: string }[];
		rules: Rule[];
	};
	knownDeviations?: { import: string }[];
};

/** The profile whose status is `required`: the one every host runs. */
export const requiredProfile = (contract: Contract) =>
	Object.entries(contract.profiles).find(([, profile]) => profile.status === "required")?.[0] ?? contract.classification.defaultProfile;

/** The profile that the contract's classification gives a module: the first
 * import from a profile namespace decides it; a module with none takes the
 * declaration, or the default. */
export function classify(imports: Import[], declared: string | undefined, contract: Contract): string {
	for (const entry of imports) {
		const named = Object.entries(contract.profiles).find(([, profile]) => profile.namespaces.includes(entry.module));
		if (named) return named[0];
	}
	return declared ?? contract.classification.defaultProfile;
}

/** What makes a module unacceptable for `profile` under the contract: an
 * import outside the profile's table or WASI, an import with another
 * signature, a missing or mistyped `handle`. Empty when it is acceptable. */
export function surfaceProblems(shape: ModuleShape, profile: string, contract: Contract): string[] {
	const problems: string[] = [];
	const table = contract.profiles[profile];
	if (!table) return [`there is no profile ${profile}`];
	for (const entry of shape.imports) {
		const label = `${entry.module}.${entry.name}`;
		const listed = table.imports.find((candidate) => candidate.module === entry.module && candidate.name === entry.name);
		const wasi = table.wasi && entry.module === table.wasi ? WASI_PREVIEW1[entry.name] : undefined;
		const expected = listed ?? wasi;
		if (entry.kind !== "func") problems.push(`${label} is a ${entry.kind} import`);
		else if (!expected) problems.push(`${label} is not in the ${profile} import table${table.wasi === entry.module ? " (the kit's WASI table)" : ""}`);
		else if (!sameSignature(entry.signature, expected)) {
			problems.push(`${label} is ${signatureText(entry.signature)}, the table has ${signatureText(expected)}`);
		}
	}
	const handle = shape.exports.find((entry) => entry.name === contract.handleExport.name && entry.kind === "func");
	if (!handle) problems.push(`it does not export ${contract.handleExport.name}`);
	else if (!sameSignature(handle.signature, contract.handleExport)) {
		problems.push(`${contract.handleExport.name} is ${signatureText(handle.signature)}, the contract has ${signatureText(contract.handleExport)}`);
	}
	return problems;
}

/** The leaves of a JSON object as dotted paths with their values. Arrays are
 * leaves. */
export function leaves(value: unknown, prefix = ""): [string, unknown][] {
	if (typeof value !== "object" || value === null || Array.isArray(value)) return [[prefix, value]];
	return Object.entries(value).flatMap(([key, member]) => leaves(member, prefix ? `${prefix}.${key}` : key));
}

/** All refusal codes a worker can report: the profile refusals and the
 * worker's own. */
export const refusalCodes = (contract: Contract) => [...contract.refusals, ...contract.worker.refusals].map((entry) => entry.code);

/** Every element of the contract that the kit must cover, as an id. A case
 * claims an id in `tests.contract`; `import:` ids are covered by the imports
 * of the modules that load instead. */
export function contractElements(contract: Contract): string[] {
	const profiles = Object.entries(contract.profiles);
	return [
		...refusalCodes(contract).map((code) => `refusal:${code}`),
		...contract.faults.map((entry) => `fault:${entry.kind}`),
		...contract.faults.map((entry) => `hostOutcome:${entry.kind}`),
		...profiles.map(([name]) => `status:${name}`),
		...profiles.flatMap(([name, profile]) => profile.handleResults.map((entry) => `handleResult:${name}:${entry.result}`)),
		...profiles.flatMap(([name, profile]) => profile.notifications.map((entry) => `notifications:${name}:${entry.id}`)),
		...profiles.flatMap(([name, profile]) => (profile.memory ?? []).map((entry) => `memory:${name}:${entry.id}`)),
		...contract.memory.map((entry) => `memory:${entry.id}`),
		...contract.classification.rules.map((entry) => `classification:${entry.id}`),
		...[...contract.bounds.requiredForQualification, ...contract.bounds.optionalForQualification].map((name) => `bound:${name}`),
		...profiles.flatMap(([name]) => [`deadline:${name}`, `wasi:${name}`]),
		...leaves(contract.policy).map(([key]) => `policy:${key}`),
		...contract.hostSession.rules.map((entry) => `hostSession:${entry.id}`),
		...contract.worker.rules.map((entry) => `worker:${entry.id}`),
		...(contract.knownDeviations ?? []).map((entry) => `deviation:${entry.import}`),
		...profiles.flatMap(([, profile]) => profile.imports.map((entry) => `import:${entry.module}.${entry.name}`)),
	];
}

/** The forms in which a document may write a number: plain digits, with
 * thousands separators, and in MiB, KiB or seconds where they divide. */
export function numberForms(value: number, unit?: "seconds"): string[] {
	if (unit === "seconds") return [`${value} seconds`, `${value} s`];
	const forms = [String(value), value.toLocaleString("en-US")];
	if (value >= 1048576 && value % 1048576 === 0) forms.push(`${value / 1048576} MiB`);
	else if (value >= 1024 && value % 1024 === 0) forms.push(`${value / 1024} KiB`);
	return forms;
}

const escapeRegExp = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const mentionsNumber = (text: string, value: number, unit?: "seconds") =>
	numberForms(value, unit).some((form) => new RegExp(`(^|[^\\d,.])${escapeRegExp(form)}(?![\\d]|,\\d)`).test(text));
const code = (text: string) => `\`${text}\``;

/** What the contract's document fails to state: each import with its
 * signature on one line, each code, fault kind, status, bound value, policy
 * value and worker argument. Empty when the document agrees with the JSON. */
export function documentProblems(contract: Contract, markdown: string): string[] {
	const problems: string[] = [];
	const lines = markdown.split(/\r?\n/);
	const line = (...parts: string[]) => lines.some((text) => parts.every((part) => text.includes(part)));
	const need = (part: string, what: string) => {
		if (!markdown.includes(part)) problems.push(`the document does not mention ${what} ${part}`);
	};
	for (const [name, profile] of Object.entries(contract.profiles)) {
		need(code(name), "the profile");
		need(code(profile.status), `the status of ${name}`);
		for (const entry of profile.imports) {
			if (!line(code(entry.name), code(signatureText(entry)))) problems.push(`the document has no line with ${code(entry.name)} and ${code(signatureText(entry))}`);
		}
		if (!mentionsNumber(markdown, profile.callDeadlineSeconds, "seconds")) problems.push(`the document does not state the ${name} call deadline of ${profile.callDeadlineSeconds} seconds`);
		if (profile.notificationAdvertisement) need(code(profile.notificationAdvertisement.illustrativeMember), "the advertisement member");
	}
	for (const entry of refusalCodes(contract)) need(code(entry), "the refusal code");
	for (const entry of contract.faults) {
		need(code(entry.kind), "the fault kind");
		if (entry.hostCode) need(code(entry.hostCode), "the host code");
		if (entry.hostOutcome) need(code(entry.hostOutcome), "the host outcome");
	}
	for (const entry of contract.hostSession.rules) if (entry.code) need(code(entry.code), "the host-session code");
	const bounds = contract.bounds;
	const numbers: [string, number][] = [
		["the memory ceiling", bounds.memoryCeilingBytes],
		["the kernel memory ceiling", bounds.kernelMemoryCeilingBytes],
		...Object.entries(bounds.instructionBudget).map(([line, value]): [string, number] => [`the ${line} instruction budget`, value]),
		["the request byte limit", contract.hostSession.frameLimits.requestBytes],
		["the response byte limit", contract.hostSession.frameLimits.responseBytes],
	];
	for (const [what, value] of numbers) if (!mentionsNumber(markdown, value)) problems.push(`the document does not state ${what}, ${value}`);
	for (const key of Object.keys(bounds.instructionBudget)) need(code(key), "the instruction budget line");
	for (const [key, value] of leaves(contract.policy)) {
		// A string is written bare, except the empty string, which is written "".
		const rendered = Array.isArray(value) ? value.map((item) => code(String(item))) : [code(typeof value === "string" && value !== "" ? value : JSON.stringify(value))];
		if (!line(code(key), ...rendered)) problems.push(`the document has no line with ${code(key)} and ${rendered.join(" ")}`);
	}
	for (const argument of contract.worker.arguments) {
		const defaults = typeof argument.default === "number" ? [argument.default] : Object.values(argument.default ?? {});
		const found = lines.some((text) => text.includes(code(argument.name)) && defaults.every((value) => mentionsNumber(text, value)));
		if (!found) problems.push(`the document has no line with ${code(argument.name)}${defaults.length ? ` and its default ${defaults.join(", ")}` : ""}`);
	}
	for (const member of [...contract.worker.startedBounds.members, ...contract.worker.startedBounds.notEnforcedReasons]) need(code(member), "the started.bounds entry");
	return problems;
}

/** The requirement and scenario names of a spec in OpenSpec Markdown. */
export function specNames(markdown: string): { requirements: Set<string>; scenarios: Set<string> } {
	const names = (pattern: RegExp) => new Set([...markdown.matchAll(pattern)].map((match) => (match[1] ?? "").trim()));
	return { requirements: names(/^### Requirement: (.+)$/gm), scenarios: names(/^#### Scenario: (.+)$/gm) };
}

/** The case ids that a fixture's leading comment names on its `;; Cases:`
 * line, or undefined when it has no leading comment. */
export function commentCases(wat: string): string[] | undefined {
	const comment: string[] = [];
	for (const line of wat.split(/\r?\n/)) {
		if (!line.startsWith(";;")) break;
		comment.push(line);
	}
	if (comment.length === 0) return undefined;
	const listed = comment.find((line) => line.startsWith(";; Cases:"));
	return listed === undefined ? [] : listed.slice(";; Cases:".length).split(",").map((id) => id.trim()).filter(Boolean);
}

export type EventMatcher = { event: string; abi?: string; code?: string; kind?: string; messageIncludes?: string[] };
export type FrameMatcher = { sameAsFrame?: number; json?: unknown; pointers?: { pointer: string; equals?: unknown; type?: string }[] };
export type Expectation = {
	exitCode?: number;
	stdoutBytes?: number;
	stdoutFrames?: FrameMatcher[];
	events?: EventMatcher[];
	noEvents?: string[];
	guestOutput?: string[];
	guestOutputIncludes?: string[];
	noGuestOutput?: string[];
	withinSeconds?: { until: "fault" | "exit"; range: [number, number] };
};
export type When = { bound: string; enforced: boolean; hostRuns?: undefined } | { hostRuns: string; runs: boolean; bound?: undefined };
export type Run = { frames: string[]; expect?: Expectation; alternatives?: { when: When; expect: Expectation }[] };
export type Case = {
	caseId: string;
	appliesTo: string;
	module: string;
	declaredAbi?: string;
	worker?: { requestBytes?: number; responseBytes?: number; omit?: string[]; buildIdentity?: "other" };
	bounds?: string[];
	tests: { requirements: string[]; scenarios?: string[]; contract?: string[] };
	runs: Run[];
	gaps?: string[];
};
export type Kit = {
	kit: string;
	version: string;
	contract: { id: string; version: string };
	assembler: { package: string; version: string };
	deadlineMarginSeconds: number;
	frames: Record<string, Record<string, unknown>>;
	modules: Record<string, { wat: string; wasm: string; sha256: string }>;
	withoutCase: { element: string; reason: string }[];
	cases: Case[];
};

export type KitInput = {
	kit: Kit;
	contract: Contract;
	/** The profile spec and the qualification spec, joined. */
	spec: string;
	/** The contract's Markdown document. */
	document: string;
	/** A file of the kit directory, by its path relative to spec/mep/mck. */
	read: (relative: string) => Uint8Array | undefined;
	/** The names of the files in the fixture directory. */
	fixtureFiles: string[];
	assemble: (name: string, wat: string) => Uint8Array;
	assemblerVersion: string | undefined;
};

export const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

const EVENTS = new Set(["started", "refused", "fault", "output"]);
const MATCHED_EVENTS = new Set(["started", "refused", "fault"]);

/** Every expectation of a run: its `expect`, or each alternative's. */
export const expectations = (run: Run): Expectation[] => [...(run.expect ? [run.expect] : []), ...(run.alternatives ?? []).map((entry) => entry.expect)];

/** The failures of the kit, one message each. Empty when the kit is sound. */
export function checkKit(input: KitInput): string[] {
	const { kit, contract } = input;
	const failures: string[] = [];
	const fail = (message: string) => failures.push(message);
	const spec = specNames(input.spec);
	const elements = new Set(contractElements(contract));
	const profiles = Object.keys(contract.profiles);
	const required = requiredProfile(contract);
	const refusals = new Set(refusalCodes(contract));
	const faultKinds = new Set(contract.faults.map((entry) => entry.kind));
	const bounds = new Set([...contract.bounds.requiredForQualification, ...contract.bounds.optionalForQualification]);
	const argumentNames = new Set(contract.worker.arguments.map((entry) => entry.name));
	const covered = new Map<string, string>();
	const cover = (element: string, by: string) => {
		if (!covered.has(element)) covered.set(element, by);
	};

	if (kit.contract.id !== contract.contract || kit.contract.version !== contract.version) {
		fail(`the kit targets ${kit.contract.id} ${kit.contract.version}, the contract is ${contract.contract} ${contract.version}`);
	}
	if (kit.assembler.package !== "wabt" || kit.assembler.version !== input.assemblerVersion) {
		fail(`the kit names ${kit.assembler.package} ${kit.assembler.version}, tools/package.json pins wabt ${input.assemblerVersion}`);
	}
	if (profiles.filter((name) => contract.profiles[name]?.status === "required").length !== 1) fail("the contract needs exactly one required profile");
	for (const [name, profile] of Object.entries(contract.profiles)) {
		if (!(profile.status in contract.statuses)) fail(`profile ${name} has the status ${profile.status}, which the contract does not define`);
	}

	const shapes = new Map<string, ModuleShape>();
	const comments = new Map<string, string[] | undefined>();
	for (const [name, module] of Object.entries(kit.modules)) {
		const wat = input.read(module.wat);
		const wasm = input.read(module.wasm);
		if (!wat) fail(`module ${name}: ${module.wat} is missing`);
		if (!wasm) fail(`module ${name}: ${module.wasm} is missing`);
		if (wasm && sha256(wasm) !== module.sha256) fail(`module ${name}: ${module.wasm} has sha256 ${sha256(wasm)}, the kit records ${module.sha256}`);
		if (wat) {
			const text = new TextDecoder().decode(wat);
			comments.set(name, commentCases(text));
			if (commentCases(text) === undefined) fail(`module ${name}: ${module.wat} has no leading ;; comment`);
			try {
				const built = input.assemble(module.wat, text);
				if (wasm && sha256(built) !== sha256(wasm)) {
					fail(`module ${name}: ${module.wasm} differs from a fresh assembly of ${module.wat} (${sha256(wasm)} != ${sha256(built)}); run with --write`);
				}
			} catch (error) {
				fail(`module ${name}: ${module.wat} does not assemble: ${String(error).split("\n").slice(0, 3).join(" ")}`);
			}
		}
		if (wasm) {
			try {
				shapes.set(name, readModule(wasm));
			} catch (error) {
				fail(`module ${name}: ${module.wasm} cannot be read: ${String(error)}`);
			}
		}
	}
	const listed = new Set(Object.values(kit.modules).flatMap((module) => [path.basename(module.wat), path.basename(module.wasm)]));
	for (const file of input.fixtureFiles) {
		if (/\.(wat|wasm)$/.test(file) && !listed.has(file)) fail(`${file} is in the fixture directory but no kit module names it`);
	}

	for (const [name, frame] of Object.entries(kit.frames)) {
		if (frame.jsonrpc !== "2.0" || typeof frame.method !== "string") fail(`frame ${name} is not a JSON-RPC 2.0 message`);
		if ("id" in frame && !Number.isInteger(frame.id)) fail(`frame ${name} has an id that is not an integer`);
	}

	const ids = new Set<string>();
	const users = new Map<string, string[]>();
	const margin = kit.deadlineMarginSeconds;
	for (const entry of kit.cases) {
		const at = `case ${entry.caseId}`;
		if (!/^[a-z0-9-]+\/[a-z0-9-]+$/.test(entry.caseId)) fail(`${at}: the id is not group/name`);
		if (ids.has(entry.caseId)) fail(`${at}: the id is used twice`);
		ids.add(entry.caseId);
		users.set(entry.module, [...(users.get(entry.module) ?? []), entry.caseId]);
		const shape = shapes.get(entry.module);
		if (!kit.modules[entry.module]) fail(`${at}: there is no module ${entry.module}`);
		if (entry.declaredAbi !== undefined && !profiles.includes(entry.declaredAbi)) fail(`${at}: the declared ABI ${entry.declaredAbi} is not a profile`);
		const omitted = entry.worker?.omit ?? [];
		for (const name of omitted) if (!argumentNames.has(name)) fail(`${at}: the worker has no argument ${name} to omit`);
		if (entry.declaredAbi === undefined && !omitted.includes("--abi")) fail(`${at}: it declares no ABI, which the worker requires; omit --abi on purpose with worker.omit`);
		if (entry.declaredAbi !== undefined && omitted.includes("--abi")) fail(`${at}: it declares an ABI and omits --abi`);
		if (entry.worker?.buildIdentity !== undefined && entry.worker.buildIdentity !== "other") fail(`${at}: worker.buildIdentity must be other`);
		if (entry.tests.requirements.length === 0) fail(`${at}: it names no requirement`);
		for (const name of entry.tests.requirements) if (!spec.requirements.has(name)) fail(`${at}: the specs have no requirement "${name}"`);
		for (const name of entry.tests.scenarios ?? []) if (!spec.scenarios.has(name)) fail(`${at}: the specs have no scenario "${name}"`);
		for (const name of entry.bounds ?? []) if (!bounds.has(name)) fail(`${at}: the contract has no bound ${name}`);
		const all = entry.runs.flatMap(expectations);
		for (const claim of entry.tests.contract ?? []) {
			if (!elements.has(claim) || claim.startsWith("import:")) fail(`${at}: ${claim} is not a claimable contract element`);
			cover(claim, entry.caseId);
			const [family, value] = [claim.split(":")[0], claim.slice(claim.indexOf(":") + 1)];
			const shows = (event: string, key: "code" | "kind") => all.some((expect) => (expect.events ?? []).some((matcher) => matcher.event === event && matcher[key] === value));
			if (family === "refusal" && !shows("refused", "code")) fail(`${at}: it claims ${claim} but no expectation shows that refusal`);
			if (family === "fault" && !shows("fault", "kind")) fail(`${at}: it claims ${claim} but no expectation shows that fault`);
		}
		for (const name of entry.bounds ?? []) cover(`bound:${name}`, entry.caseId);
		const profile = shape ? classify(shape.imports, entry.declaredAbi, contract) : undefined;
		const deadline = profile ? (contract.profiles[profile]?.callDeadlineSeconds ?? 0) : 0;
		const byHost = entry.runs.some((run) => (run.alternatives ?? []).some((alternative) => alternative.when.hostRuns !== undefined));
		if (!profiles.includes(entry.appliesTo)) fail(`${at}: appliesTo ${entry.appliesTo} is not a profile`);
		else if (profile) {
			const expected = byHost || profile === required ? required : profile;
			if (entry.appliesTo !== expected) {
				fail(`${at}: it applies to ${entry.appliesTo}, but its module is ${profile}${byHost ? " and it selects by the host's profiles" : ""}, so it applies to ${expected}`);
			}
		}
		if (entry.runs.length === 0) fail(`${at}: it has no run`);
		entry.runs.forEach((run, index) => {
			const where = `${at} run ${index}`;
			for (const frame of run.frames) if (!kit.frames[frame]) fail(`${where}: there is no frame ${frame}`);
			if (!!run.expect === !!run.alternatives) fail(`${where}: it needs exactly one of expect and alternatives`);
			for (const alternative of run.alternatives ?? []) {
				const when = alternative.when;
				if (when.hostRuns !== undefined) {
					if (!profiles.includes(when.hostRuns) || when.hostRuns === required) fail(`${where}: hostRuns ${when.hostRuns} is not a profile that a host may leave out`);
				} else {
					if (!bounds.has(when.bound)) fail(`${where}: the contract has no bound ${when.bound}`);
					cover(`bound:${when.bound}`, entry.caseId);
				}
			}
			for (const expect of expectations(run)) {
				if (expect.exitCode !== undefined && ![0, 1, 2, 3].includes(expect.exitCode)) fail(`${where}: exit status ${expect.exitCode} is not a worker status`);
				const refused = (expect.events ?? []).some((matcher) => matcher.event === "refused");
				if (expect.exitCode === 3 && !refused) fail(`${where}: exit status 3 needs a refused event`);
				if (refused && !(expect.noEvents ?? []).includes("started")) fail(`${where}: a refusal comes instead of started, so noEvents must name started`);
				for (const matcher of expect.events ?? []) {
					if (!MATCHED_EVENTS.has(matcher.event)) fail(`${where}: ${matcher.event} is not a matched worker event (guest output goes in guestOutput)`);
					if (matcher.event === "refused" && !refusals.has(matcher.code ?? "")) fail(`${where}: ${matcher.code} is not a contract refusal code`);
					if (matcher.event === "fault" && matcher.kind !== undefined && !faultKinds.has(matcher.kind)) fail(`${where}: ${matcher.kind} is not a contract fault kind`);
					if (matcher.event === "started" && matcher.abi !== profile) fail(`${where}: started.abi ${matcher.abi} differs from the classified profile ${profile}`);
				}
				for (const name of expect.noEvents ?? []) if (!EVENTS.has(name)) fail(`${where}: ${name} is not a worker event`);
				for (const frame of expect.stdoutFrames ?? []) {
					if (frame.sameAsFrame !== undefined && !(frame.sameAsFrame >= 0 && frame.sameAsFrame < run.frames.length)) fail(`${where}: sameAsFrame ${frame.sameAsFrame} is not a frame of the run`);
				}
				if (expect.withinSeconds) {
					const [low, high] = expect.withinSeconds.range;
					const kinds = (expect.events ?? []).filter((matcher) => matcher.event === "fault").map((matcher) => matcher.kind);
					if (high > deadline + margin || low < 0 || low > high) fail(`${where}: [${low}, ${high}] does not follow from the ${profile} deadline of ${deadline} s`);
					if (kinds.includes("call-deadline") && (low !== deadline || high !== deadline + margin)) fail(`${where}: a call-deadline fault needs [${deadline}, ${deadline + margin}]`);
					if (kinds.includes("budget-exhausted") && (low !== 0 || high !== deadline)) fail(`${where}: a budget-exhausted fault needs [0, ${deadline}]`);
				}
			}
		});
		const loads = all.length > 0 && all.every((expect) => (expect.events ?? []).some((matcher) => matcher.event === "started"));
		if (shape && profile && loads) {
			if (entry.declaredAbi !== undefined && entry.declaredAbi !== profile) fail(`${at}: the module is ${profile} but the case declares ${entry.declaredAbi}`);
			for (const problem of surfaceProblems(shape, profile, contract)) fail(`${at}: module ${entry.module} is meant to load, but ${problem}`);
			for (const imported of shape.imports) cover(`import:${imported.module}.${imported.name}`, entry.caseId);
		}
	}

	for (const [name, cases] of users) {
		const named = comments.get(name);
		if (!kit.modules[name] || named === undefined) continue;
		const missing = cases.filter((id) => !named.includes(id));
		const stale = named.filter((id) => !cases.includes(id));
		if (missing.length || stale.length) {
			fail(`module ${name}: its ;; Cases: line names [${named.join(", ")}], the cases that use it are [${cases.join(", ")}]`);
		}
	}
	for (const name of Object.keys(kit.modules)) if (!users.has(name)) fail(`module ${name} is used by no case`);
	const exempt = new Set<string>();
	for (const entry of kit.withoutCase ?? []) {
		if (!elements.has(entry.element)) fail(`withoutCase lists ${entry.element}, which is not a contract element`);
		if (!entry.reason?.trim()) fail(`withoutCase lists ${entry.element} without a reason`);
		if (covered.has(entry.element)) fail(`withoutCase lists ${entry.element}, but case ${covered.get(entry.element)} covers it`);
		exempt.add(entry.element);
	}
	for (const element of elements) if (!covered.has(element) && !exempt.has(element)) fail(`the contract element ${element} has no case`);
	for (const problem of documentProblems(contract, input.document)) fail(problem);
	return failures;
}

/** The assembler: wabt with FEATURES, without debug names. */
export async function assembler(): Promise<(name: string, wat: string) => Uint8Array> {
	const wabt = await wabtInit();
	const features = FEATURES as Parameters<typeof wabt.parseWat>[2];
	return (name, wat) => {
		const module = wabt.parseWat(name, wat, features);
		try {
			module.resolveNames();
			(module.validate as (options?: unknown) => void)(features);
			return new Uint8Array(module.toBinary({ log: false, write_debug_names: false }).buffer);
		} finally {
			module.destroy();
		}
	};
}

/** A spec under openspec/specs once its change is archived, otherwise the
 * delta of the one active change that has it. `relative` is its path below
 * the specs directory, such as mep/wasm-execution-profiles/spec.md. */
export function findSpec(root: string, relative: string): string {
	const main = `openspec/specs/${relative}`;
	if (existsSync(path.join(root, main))) return main;
	const changes = readdirSync(path.join(root, "openspec/changes"))
		.filter((name) => name !== "archive" && existsSync(path.join(root, "openspec/changes", name, "specs", relative)))
		.map((name) => `openspec/changes/${name}/specs/${relative}`);
	if (changes.length !== 1) throw new Error(`expected one ${relative}, found ${changes.length}: ${changes.join(", ")}`);
	return changes[0] as string;
}

/** The kit text with each module's sha256 replaced by `digests[name]`. */
export function withDigests(text: string, digests: Record<string, string>): string {
	let result = text;
	for (const [name, digest] of Object.entries(digests)) {
		const pattern = new RegExp(`("${name}":\\s*\\{[^}]*"sha256":\\s*")[0-9a-f]*(")`);
		if (!pattern.test(result)) throw new Error(`the kit has no module entry ${name} to write a digest into`);
		result = result.replace(pattern, `$1${digest}$2`);
	}
	return result;
}

/** Everything checkKit needs, read from the repository at `root`. */
export async function loadKit(root: string): Promise<KitInput> {
	const kitDir = path.join(root, KIT_DIR);
	const packageJson = JSON.parse(readFileSync(path.join(root, "tools/package.json"), "utf8")) as { devDependencies?: Record<string, string> };
	const specs = [PROFILE_SPEC, QUALIFICATION_SPEC].map((relative) => readFileSync(path.join(root, findSpec(root, relative)), "utf8"));
	return {
		kit: JSON.parse(readFileSync(path.join(root, KIT), "utf8")) as Kit,
		contract: JSON.parse(readFileSync(path.join(root, CONTRACT), "utf8")) as Contract,
		spec: specs.join("\n"),
		document: readFileSync(path.join(root, DOCUMENT), "utf8"),
		read: (relative) => {
			const file = path.join(kitDir, relative);
			return existsSync(file) ? new Uint8Array(readFileSync(file)) : undefined;
		},
		fixtureFiles: readdirSync(path.join(root, FIXTURES)),
		assemble: await assembler(),
		assemblerVersion: packageJson.devDependencies?.wabt,
	};
}

async function main(): Promise<void> {
	const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
	const input = await loadKit(root);
	if (process.argv.includes("--write")) {
		const digests: Record<string, string> = {};
		for (const [name, module] of Object.entries(input.kit.modules)) {
			const wat = input.read(module.wat);
			if (!wat) continue;
			const built = input.assemble(module.wat, new TextDecoder().decode(wat));
			writeFileSync(path.join(root, KIT_DIR, module.wasm), built);
			digests[name] = sha256(built);
		}
		writeFileSync(path.join(root, KIT), withDigests(readFileSync(path.join(root, KIT), "utf8"), digests));
		console.error(`Assembled ${Object.keys(digests).length} modules and refreshed their digests.`);
		Object.assign(input, await loadKit(root));
	}
	const failures = checkKit(input);
	if (failures.length > 0) {
		console.error(failures.join("\n"));
		console.error(`\nThe WASM host kit has ${failures.length} failures.`);
		process.exit(1);
	}
	const applying = (profile: string) => input.kit.cases.filter((entry) => entry.appliesTo === profile).length;
	console.error(
		`WASM host kit: ${input.kit.cases.length} cases (${Object.keys(input.contract.profiles)
			.map((profile) => `${applying(profile)} for ${profile}`)
			.join(", ")}) and ${Object.keys(input.kit.modules).length} modules check against ${input.contract.contract} ${input.contract.version}.`,
	);
}

if (import.meta.main) await main();
