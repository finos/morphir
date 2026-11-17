// Checks the fixed examples of the Morphir file context (ir-context 0.1.0-draft.1) and the fixed cases of the writer
// policy morphir.compact/0.1.0-draft.1.
//
//   bun run tools/check-ir-context.ts            # check docs/spec/ir/context/examples and .../policy
//
// The examples are data for readers in other repositories. This script states nothing about the contract that
// openspec/changes/add-bounded-model-access/specs/ir/name-compaction/spec.md does not already state; it checks that
// each example is what docs/spec/ir/context/examples/cases.json says it is:
//
// - the envelope JSON Schema accepts exactly the cases marked `schemaValid`;
// - the reader rules a schema cannot state (duplicate table members, member order, unresolved references) and the
//   ones it can (declared URL, envelope shape, critical paths, limits, the form of each spelling) give exactly the
//   case's expected diagnostic, or none;
// - each valid example's expanded twin is the example with every reference replaced by its spelling, and the twin
//   is a valid plain document of its IR version and file kind.
//
// The rules here find references by shape: any object that is exactly {"$name": <string>}. The examples hold no such
// object outside a typed name position, so shape and position agree on them; a reader resolves by position.
// The expansion check also does not choose the table from the position: it accepts a reference when one of the
// tables defining its id gives the twin's value. Position typing is the reader's job, tested where readers live.
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

/** A parsed JSON value that keeps every object member in order, duplicates included. */
export type Ordered = null | boolean | number | string | Ordered[] | { members: [string, Ordered][] };

/** Parses JSON text without losing member order or duplicate members, which `JSON.parse` drops. */
export function parseOrdered(text: string): Ordered {
	let at = 0;
	const fail = (what: string): never => {
		throw new Error(`invalid JSON at offset ${at}: ${what}`);
	};
	const space = () => {
		while (at < text.length && " \t\n\r".includes(text[at]!)) at++;
	};
	const literal = (word: string, value: Ordered): Ordered => {
		if (text.startsWith(word, at)) {
			at += word.length;
			return value;
		}
		return fail(`expected ${word}`);
	};
	const string = (): string => {
		const start = at;
		at++;
		while (at < text.length && text[at] !== '"') at += text[at] === "\\" ? 2 : 1;
		if (at >= text.length) fail("unterminated string");
		at++;
		return JSON.parse(text.slice(start, at)) as string;
	};
	const value = (): Ordered => {
		space();
		const c = text[at];
		if (c === "{") {
			at++;
			const members: [string, Ordered][] = [];
			space();
			if (text[at] === "}") {
				at++;
				return { members };
			}
			for (;;) {
				space();
				if (text[at] !== '"') fail("expected a member name");
				const key = string();
				space();
				if (text[at] !== ":") fail("expected :");
				at++;
				members.push([key, value()]);
				space();
				if (text[at] === ",") {
					at++;
					continue;
				}
				if (text[at] === "}") {
					at++;
					return { members };
				}
				fail("expected , or }");
			}
		}
		if (c === "[") {
			at++;
			const items: Ordered[] = [];
			space();
			if (text[at] === "]") {
				at++;
				return items;
			}
			for (;;) {
				items.push(value());
				space();
				if (text[at] === ",") {
					at++;
					continue;
				}
				if (text[at] === "]") {
					at++;
					return items;
				}
				fail("expected , or ]");
			}
		}
		if (c === '"') return string();
		if (c === "t") return literal("true", true);
		if (c === "f") return literal("false", false);
		if (c === "n") return literal("null", null);
		const number = /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/.exec(text.slice(at));
		if (number === null) return fail("unexpected character");
		at += number[0].length;
		return Number(number[0]);
	};
	const result = value();
	space();
	if (at !== text.length) fail("trailing text");
	return result;
}

const isObject = (v: Ordered | undefined): v is { members: [string, Ordered][] } => typeof v === "object" && v !== null && !Array.isArray(v);
const member = (v: Ordered | undefined, key: string): Ordered | undefined => (isObject(v) ? v.members.find(([k]) => k === key)?.[1] : undefined);

/** The ir-context draft this checker knows. */
export const CONTEXT_SCHEMA_URL = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json";
export const TABLES = ["names", "packagePaths", "modulePaths", "fqNames"] as const;
export type Table = (typeof TABLES)[number];
/** Draft.1's recognized critical paths. */
export const CRITICAL_PATHS = ["$schema", "context", ...TABLES.map(t => `context.${t}`), "critical", "document"];
export type Limits = { maxTableEntries: number; maxSpellingBytes: number };

/** Whether a value is a reference: an object with exactly one member, `$name`, holding a string. */
export function referenceId(v: Ordered | undefined): string | undefined {
	if (!isObject(v) || v.members.length !== 1) return undefined;
	const [key, id] = v.members[0]!;
	return key === "$name" && typeof id === "string" ? id : undefined;
}

function references(v: Ordered, out: string[] = []): string[] {
	const id = referenceId(v);
	if (id !== undefined) out.push(id);
	else if (Array.isArray(v)) for (const item of v) references(item, out);
	else if (isObject(v)) for (const [, m] of v.members) references(m, out);
	return out;
}

/** A name by the grammar of docs/spec/draft/names.md: `-`-joined segments, each a word or an initialism. */
const NAME = /^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$/;

/**
 * Whether a spelling is one of its table's type: a name, a `/`-separated path of names, or a `package:module#name`
 * FQName. A name is a sequence of segments, and its canonical form writes each segment as it is read (a word in
 * lowercase, an initialism in uppercase, joined by `-`), so every spelling the grammar accepts is canonical.
 * Spellings are never read through the classic word arrays, which cannot hold an initialism such as `FR2052A`.
 */
export function isSpelling(table: Table, spelling: string): boolean {
	const isPath = (text: string) => text.split("/").every(n => NAME.test(n));
	if (table === "names") return NAME.test(spelling);
	if (table !== "fqNames") return isPath(spelling);
	const match = /^([^:#]+):([^:#]+)#([^:#]+)$/.exec(spelling);
	return match !== null && isPath(match[1]!) && isPath(match[2]!) && NAME.test(match[3]!);
}

/**
 * The reader diagnostics a file gives, in the order a whole-file reader checks them. A file whose top level is not an
 * object with `$schema` is a plain document and gives none here.
 */
export function contextDiagnostics(text: string, limits: Limits): string[] {
	const root = parseOrdered(text);
	if (!isObject(root)) return [];
	const schema = member(root, "$schema");
	if (schema === undefined) return [];
	if (schema !== CONTEXT_SCHEMA_URL) return ["context.undeclared_schema"];
	const keys = root.members.map(([k]) => k);
	if (keys.indexOf("document") >= 0 && keys.indexOf("context") > keys.indexOf("document")) return ["context.after_document"];
	const found: string[] = [];
	const report = (code: string) => {
		if (!found.includes(code)) found.push(code);
	};
	const context = member(root, "context");
	const critical = member(root, "critical");
	const criticalIsList = critical === undefined || (Array.isArray(critical) && critical.every(p => typeof p === "string"));
	if (!isObject(context) || !isObject(member(root, "document")) || !criticalIsList) return ["context.invalid_envelope"];
	const duplicated = (o: { members: [string, Ordered][] }) => new Set(o.members.map(([k]) => k)).size !== o.members.length;
	if (duplicated(root) || duplicated(context) || TABLES.some(t => isObject(member(context, t)) && duplicated(member(context, t) as { members: [string, Ordered][] }))) report("context.duplicate_entry");
	if (Array.isArray(critical) && critical.some(p => !CRITICAL_PATHS.includes(p as string))) report("context.unknown_critical");
	const defined = new Set<string>();
	for (const t of TABLES) {
		const table = member(context, t);
		if (table === undefined) continue;
		if (!isObject(table)) {
			report("context.invalid_entry");
			continue;
		}
		// The count comes first: an oversized table is refused without reading its entries.
		if (table.members.length > limits.maxTableEntries) {
			report("context.too_many_entries");
			continue;
		}
		for (const [id, spelling] of table.members) {
			defined.add(id);
			if (!/^[A-Za-z][A-Za-z0-9]*$/.test(id) || typeof spelling !== "string") report("context.invalid_entry");
			else if (Buffer.byteLength(spelling, "utf8") > limits.maxSpellingBytes) report("context.name_too_long");
			else if (!isSpelling(t, spelling)) report("context.invalid_entry");
		}
	}
	if (found.length > 0) return found;
	if (references(member(root, "document")!).some(id => !defined.has(id))) found.push("context.unknown_alias");
	return found;
}

/** The classic v3 word arrays of a canonical name: a word stays, an initialism becomes one-letter words. */
export function classicName(name: string): string[] {
	return name.split("-").flatMap(segment => {
		if (/^[a-z0-9]+$/.test(segment)) return [segment];
		if (/^[A-Z]+$/.test(segment)) return [...segment.toLowerCase()];
		throw new Error(`the checker cannot decode the initialism ${segment}`);
	});
}
export const classicPath = (p: string): string[][] => p.split("/").map(classicName);
export function classicFqName(fq: string): [string[][], string[][], string[]] {
	const match = /^([^:]+):([^#]+)#(.+)$/.exec(fq);
	if (match === null) throw new Error(`not an FQName: ${fq}`);
	return [classicPath(match[1]!), classicPath(match[2]!), classicName(match[3]!)];
}

/** Plain JSON of an ordered value; the first of duplicate members wins (no example with duplicates is expanded). */
export function plain(v: Ordered): unknown {
	if (Array.isArray(v)) return v.map(plain);
	if (isObject(v)) {
		const out: Record<string, unknown> = {};
		for (const [k, m] of v.members) if (!Object.hasOwn(out, k)) out[k] = plain(m);
		return out;
	}
	return v;
}

/**
 * Problems found comparing a valid example's document with its expanded twin: equal everywhere, except that each
 * reference stands for the twin's value there, which must be the spelling of one of the tables defining its id,
 * encoded as the twin encodes it (a canonical string, or classic arrays in a classic v3 slot).
 */
export function expansionProblems(example: Ordered, twin: unknown): string[] {
	const context = member(example, "context");
	const tables = new Map<Table, Map<string, string>>();
	for (const t of TABLES) {
		const table = member(context, t);
		tables.set(t, new Map(isObject(table) ? table.members.filter(([, s]) => typeof s === "string").map(([id, s]) => [id, s as string]) : []));
	}
	const encodings = (t: Table, spelling: string): unknown[] => {
		const classic = t === "names" ? classicName(spelling) : t === "fqNames" ? classicFqName(spelling) : classicPath(spelling);
		return [spelling, classic];
	};
	const problems: string[] = [];
	const walk = (v: Ordered, expected: unknown, at: string) => {
		const id = referenceId(v);
		if (id !== undefined) {
			const matches = TABLES.filter(t => tables.get(t)!.has(id)).some(t => encodings(t, tables.get(t)!.get(id)!).some(e => Bun.deepEquals(e, expected, true)));
			if (!matches) problems.push(`${at}: {"$name":"${id}"} does not expand to ${JSON.stringify(expected)}`);
			return;
		}
		if (Array.isArray(v)) {
			if (!Array.isArray(expected) || expected.length !== v.length) problems.push(`${at}: array differs`);
			else v.forEach((item, i) => walk(item, expected[i], `${at}/${i}`));
			return;
		}
		if (isObject(v)) {
			if (typeof expected !== "object" || expected === null || Array.isArray(expected)) {
				problems.push(`${at}: object differs`);
				return;
			}
			const keys = v.members.map(([k]) => k).sort();
			if (!Bun.deepEquals(keys, Object.keys(expected).sort())) problems.push(`${at}: members ${keys} differ from ${Object.keys(expected).sort()}`);
			for (const [k, m] of v.members) walk(m, (expected as Record<string, unknown>)[k], `${at}/${k}`);
			return;
		}
		if (v !== expected) problems.push(`${at}: ${JSON.stringify(v)} differs from ${JSON.stringify(expected)}`);
	};
	walk(member(example, "document")!, twin, "#/document");
	return problems;
}

/** Validates a JSON value against a schema with the sourcemeta `jsonschema` CLI, as the other parent checks do. */
export function schemaAccepts(schema: string, value: unknown, resolve: string[] = []): boolean {
	const temp = mkdtempSync(path.join(tmpdir(), "morphir-ir-context-"));
	try {
		const instance = path.join(temp, "instance.json");
		writeFileSync(instance, JSON.stringify(value));
		return schemaAcceptsFile(schema, instance, resolve);
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

export function schemaAcceptsFile(schema: string, instance: string, resolve: string[] = []): boolean {
	const result = spawnSync("jsonschema", ["validate", schema, instance, ...resolve.flatMap(r => ["--resolve", r])], { encoding: "utf8", windowsHide: true, timeout: 60_000 });
	if (result.error !== undefined || result.signal !== null) throw new Error(`jsonschema did not run: ${result.error?.message ?? result.signal}`);
	if (result.status !== 0 && result.status !== 2) throw new Error(`jsonschema failed on ${instance}: ${result.stdout}${result.stderr}`);
	return result.status === 0;
}

/** The plain IR schema, and the definition in it, that an expanded twin of this version and kind must satisfy. */
export function plainSchemaOf(ir: number, kind: string): { file: string; definition?: string } | undefined {
	if (kind === "single-file") return { file: `website/static/schemas/morphir-ir-v${ir}.json` };
	// A v3 tree file has no JSON Schema; docs/spec/ir/schemas/v3/document-tree-files.md defines it.
	if (ir === 3) return undefined;
	const definition = { manifest: "DistributionManifestFile", module: "ModuleManifestFile", type: "TypeDefinitionFile", value: "ValueDefinitionFile" }[kind];
	return definition === undefined ? undefined : { file: "website/static/schemas/morphir-ir-v4-document-tree-files.json", definition };
}

export function plainSchemaAccepts(root: string, ir: number, kind: string, value: unknown): boolean | undefined {
	const target = plainSchemaOf(ir, kind);
	if (target === undefined) return undefined;
	const file = path.join(root, target.file);
	if (target.definition === undefined) return schemaAccepts(file, value);
	const temp = mkdtempSync(path.join(tmpdir(), "morphir-ir-context-ref-"));
	try {
		const id = (JSON.parse(readFileSync(file, "utf8")) as { $id: string }).$id;
		const wrapper = path.join(temp, "wrapper.json");
		writeFileSync(wrapper, JSON.stringify({ $schema: "https://json-schema.org/draft/2020-12/schema", $ref: `${id}#/definitions/${target.definition}` }));
		return schemaAccepts(wrapper, value, [file]);
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

export type ExampleCase = { id: string; file: string; expanded?: string; ir: number; kind: string; expected: string; schemaValid: boolean };
export type ExampleIndex = { schema: string; schemaUrl: string; limits: Limits; cases: ExampleCase[] };
export const EXAMPLES_DIR = "docs/spec/ir/context/examples";

/** Every problem with the fixed examples; empty when each case is what its index row says. */
export function exampleProblems(root: string, dir = EXAMPLES_DIR): string[] {
	const index = JSON.parse(readFileSync(path.join(root, dir, "cases.json"), "utf8")) as ExampleIndex;
	const schema = path.join(root, index.schema);
	const problems: string[] = [];
	if (index.schemaUrl !== CONTEXT_SCHEMA_URL) problems.push(`cases.json names ${index.schemaUrl}, not ${CONTEXT_SCHEMA_URL}`);
	if ((JSON.parse(readFileSync(schema, "utf8")) as { $id: string }).$id !== CONTEXT_SCHEMA_URL) problems.push(`${index.schema} does not have the $id ${CONTEXT_SCHEMA_URL}`);
	for (const c of index.cases) {
		const file = path.join(root, dir, c.file);
		const text = readFileSync(file, "utf8");
		const accepted = schemaAcceptsFile(schema, file);
		if (accepted !== c.schemaValid) problems.push(`${c.id}: the schema ${accepted ? "accepts" : "refuses"} it, but cases.json says schemaValid ${c.schemaValid}`);
		const diagnostics = contextDiagnostics(text, index.limits);
		const expected = c.expected === "valid" ? [] : [c.expected];
		if (!Bun.deepEquals(diagnostics, expected)) problems.push(`${c.id}: reader rules give [${diagnostics}], expected [${expected}]`);
		if (c.expected === "valid") {
			if (c.expanded === undefined) {
				problems.push(`${c.id}: a valid case names no expanded twin`);
				continue;
			}
			const twin = JSON.parse(readFileSync(path.join(root, dir, c.expanded), "utf8")) as unknown;
			for (const p of expansionProblems(parseOrdered(text), twin)) problems.push(`${c.id}: ${p}`);
			const formatVersion = (twin as { formatVersion?: unknown }).formatVersion;
			if (!Bun.deepEquals(formatVersion, plain(member(member(parseOrdered(text), "document"), "formatVersion")!))) problems.push(`${c.id}: the twin's formatVersion differs from the document's`);
			if (plainSchemaAccepts(root, c.ir, c.kind, twin) === false) problems.push(`${c.id}: the expanded twin is not a valid plain v${c.ir} ${c.kind} document`);
		}
	}
	return problems;
}

/**
 * RFC 8785 canonical JSON of a parsed value: members sorted by UTF-16 code units (JavaScript's default string order),
 * no whitespace, and ECMAScript string and number serialization, which RFC 8785 adopts.
 */
export function jcs(v: Ordered): string {
	if (Array.isArray(v)) return `[${v.map(jcs).join(",")}]`;
	if (isObject(v)) {
		const members = [...v.members].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
		return `{${members.map(([k, m]) => `${JSON.stringify(k)}:${jcs(m)}`).join(",")}}`;
	}
	if (typeof v === "number" && !Number.isFinite(v)) throw new Error("JCS has no form for a non-finite number");
	return JSON.stringify(v);
}

/** Why bytes are not RFC 8785 JCS, or undefined when they are: valid UTF-8, no duplicate member, the canonical text. */
export function jcsProblem(bytes: Uint8Array): string | undefined {
	let text: string;
	try {
		text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
	} catch {
		return "not valid UTF-8";
	}
	let parsed: Ordered;
	try {
		parsed = parseOrdered(text);
	} catch (error) {
		return String(error);
	}
	const duplicate = (v: Ordered): boolean =>
		Array.isArray(v) ? v.some(duplicate) : isObject(v) ? new Set(v.members.map(([k]) => k)).size !== v.members.length || v.members.some(([, m]) => duplicate(m)) : false;
	if (duplicate(parsed)) return "a member appears twice";
	const canonical = jcs(parsed);
	if (canonical !== text) {
		let at = 0;
		while (at < text.length && text[at] === canonical[at]) at++;
		return `not canonical from character ${at}: ${JSON.stringify(text.slice(at, at + 40))} where JCS has ${JSON.stringify(canonical.slice(at, at + 40))}`;
	}
	return undefined;
}

export type PolicyCase = { id: string; ir: number; kind: string; compacted: boolean };
export type PolicyIndex = { policy: string; schema: string; cases: PolicyCase[] };
export const POLICY_DIR = "docs/spec/ir/context/policy/morphir.compact-0.1.0-draft.1";

/**
 * Every problem with the policy's fixed cases. This checks the form of each expected file only (JCS, the envelope
 * schema for a compacted one, no envelope for a plain one) and that each input is a valid plain document; it never
 * computes what the policy would write. The expected bytes are worked out by hand in each case's README.
 */
export function policyProblems(root: string, dir = POLICY_DIR): string[] {
	const index = JSON.parse(readFileSync(path.join(root, dir, "cases.json"), "utf8")) as PolicyIndex;
	const problems: string[] = [];
	if (index.policy !== "morphir.compact/0.1.0-draft.1") problems.push(`cases.json names the policy ${index.policy}`);
	const schema = path.join(root, index.schema);
	for (const c of index.cases) {
		const at = path.join(root, dir, "cases", c.id);
		const bytes = readFileSync(path.join(at, "expected.json"));
		const problem = jcsProblem(bytes);
		if (problem !== undefined) {
			problems.push(`${c.id}: expected.json is not JCS: ${problem}`);
			continue;
		}
		const expected = parseOrdered(new TextDecoder().decode(bytes));
		const envelope = member(expected, "$schema") !== undefined;
		if (envelope !== c.compacted) problems.push(`${c.id}: cases.json says compacted ${c.compacted}, but expected.json ${envelope ? "has" : "has no"} envelope`);
		if (envelope && !schemaAcceptsFile(schema, path.join(at, "expected.json"))) problems.push(`${c.id}: expected.json does not satisfy ${index.schema}`);
		if (envelope && contextDiagnostics(new TextDecoder().decode(bytes), { maxTableEntries: 16384, maxSpellingBytes: 1024 }).length > 0) problems.push(`${c.id}: expected.json breaks a reader rule`);
		const input = JSON.parse(readFileSync(path.join(at, "input.json"), "utf8")) as unknown;
		if (plainSchemaAccepts(root, c.ir, c.kind, input) === false) problems.push(`${c.id}: input.json is not a valid plain v${c.ir} ${c.kind} document`);
		if (!existsSync(path.join(at, "README.md"))) problems.push(`${c.id}: no README.md with the hand computation`);
	}
	return problems;
}

if (import.meta.main) {
	const root = path.resolve(import.meta.dir, "..");
	const problems = [...exampleProblems(root), ...policyProblems(root)];
	for (const p of problems) console.error(p);
	if (problems.length > 0) process.exit(1);
	console.log("ir-context examples and morphir.compact/0.1.0-draft.1 cases: every case is what its cases.json says it is");
}
