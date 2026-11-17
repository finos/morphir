// The fixed examples of the Morphir file context, and the checks behind tools/check-ir-context.ts.
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";

import {
	CONTEXT_SCHEMA_URL,
	EXAMPLES_DIR,
	type ExampleIndex,
	canonicalSpelling,
	classicFqName,
	classicName,
	contextDiagnostics,
	exampleProblems,
	expansionProblems,
	jcsProblem,
	parseOrdered,
	plainSchemaAccepts,
	POLICY_DIR,
	type PolicyIndex,
	policyProblems,
	schemaAccepts,
} from "./check-ir-context";

const root = path.resolve(import.meta.dir, "..");
const examples = path.join(root, EXAMPLES_DIR);
const read = (file: string) => readFileSync(path.join(examples, file), "utf8");
const index = JSON.parse(read("cases.json")) as ExampleIndex;
const schema = path.join(root, index.schema);

describe("ir-context examples", () => {
	test("every example is what cases.json says it is", () => {
		expect(exampleProblems(root)).toEqual([]);
	}, 180_000);

	test("the index covers both single files and every tree file kind at v3 and v4, and every refusal", () => {
		const valid = index.cases.filter(c => c.expected === "valid").map(c => `v${c.ir}-${c.kind}`).sort();
		expect(valid).toEqual(["v3-manifest", "v3-module", "v3-single-file", "v3-type", "v3-value", "v4-manifest", "v4-module", "v4-single-file", "v4-type", "v4-value"]);
		const refusals = index.cases.filter(c => c.expected !== "valid").map(c => c.expected).sort();
		expect(refusals).toEqual([
			"context.after_document", "context.duplicate_entry", "context.invalid_entry", "context.invalid_envelope", "context.name_too_long",
			"context.too_many_entries", "context.undeclared_schema", "context.unknown_alias", "context.unknown_critical",
		]);
		expect(index.limits).toEqual({ maxTableEntries: 16384, maxSpellingBytes: 1024 });
	});

	test("the README states the limits that cases.json and the schema use", () => {
		const readme = read("README.md");
		expect(readme).toContain("16,384");
		expect(readme).toContain("1,024");
		const text = readFileSync(schema, "utf8");
		expect(text.match(/"maxProperties": 16384/g)).toHaveLength(4);
		expect(text.match(/"maxLength": 1024/g)).toHaveLength(3);
	});

	test("the limits are one over in the over-limit examples, and exactly at them is accepted", () => {
		const many = parseOrdered(read("invalid/too-many-entries.json")) as { members: [string, unknown][] };
		const names = (many.members.find(([k]) => k === "context")![1] as { members: [string, { members: unknown[] }][] }).members.find(([k]) => k === "names")![1];
		expect(names.members).toHaveLength(16385);
		const long = (JSON.parse(read("invalid/name-too-long.json")) as { context: { names: { t: string } } }).context.names.t;
		expect(Buffer.byteLength(long, "utf8")).toBe(1025);
		const atLimit = read("invalid/name-too-long.json").replace(long, long.slice(0, 1023) + "x");
		expect(contextDiagnostics(atLimit, index.limits)).toEqual([]);
		expect(schemaAccepts(schema, JSON.parse(atLimit))).toBe(true);
	}, 60_000);
});

describe("morphir.compact/0.1.0-draft.1 fixed cases", () => {
	const policyDir = path.join(root, POLICY_DIR);
	const policy = JSON.parse(readFileSync(path.join(policyDir, "cases.json"), "utf8")) as PolicyIndex;

	test("every expected file is JCS and has the form its row says, and every input is a valid plain document", () => {
		expect(policyProblems(root)).toEqual([]);
	}, 180_000);

	test("the cases cover each file kind at v3 and v4 and each policy rule", () => {
		const ids = policy.cases.map(c => c.id).sort();
		expect(ids).toEqual([
			"alias-allocation-order", "look-alike-literal", "loss", "loss-boundary-accepted", "loss-boundary-declined",
			"name-used-once", "non-ascii-content", "table-order", "tie",
			"v3-manifest", "v3-module", "v3-single-file", "v3-type", "v3-value",
			"v4-manifest", "v4-module", "v4-single-file", "v4-type", "v4-value",
		]);
		expect(policy.cases.filter(c => !c.compacted).map(c => c.id).sort()).toEqual(["loss", "loss-boundary-declined", "v3-manifest", "v4-manifest"]);
	});

	test("non-ASCII content is written raw, as two UTF-8 bytes per letter", () => {
		const bytes = readFileSync(path.join(policyDir, "cases/non-ascii-content/expected.json"));
		expect(bytes.includes(Buffer.from("réduit", "utf8"))).toBe(true);
		expect(bytes.includes(Buffer.from("\\u00e9"))).toBe(false);
	});

	test("JCS problems are found: order, whitespace, escapes, numbers, duplicates, a trailing newline", () => {
		const bytes = (text: string) => new TextEncoder().encode(text);
		expect(jcsProblem(bytes('{"a":1,"b":[true,null,"é"]}'))).toBeUndefined();
		expect(jcsProblem(bytes('{"B":1,"a":2}'))).toBeUndefined();
		for (const bad of ['{"b":1,"a":2}', '{"a": 1}', '{"a":"\\u00e9"}', '{"a":1.0}', '{"a":1,"a":1}', '{"a":1}\n', '{"a":"\\/"}']) {
			expect(jcsProblem(bytes(bad)), bad).toBeDefined();
		}
		expect(jcsProblem(new Uint8Array([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d]))).toBe("not valid UTF-8");
	});
});

describe("the checker can fail", () => {
	test("a plain document has no context diagnostics", () => {
		expect(contextDiagnostics(read("expanded/v4-type.json"), index.limits)).toEqual([]);
		expect(contextDiagnostics("[1]", index.limits)).toEqual([]);
	});

	test("a malformed envelope is context.invalid_envelope, and the order and the schema URL are checked before it", () => {
		const valid = JSON.parse(read("valid/v4-type.json")) as Record<string, unknown>;
		const envelope = (change: (e: Record<string, unknown>) => void) => {
			const e = structuredClone(valid);
			change(e);
			return contextDiagnostics(JSON.stringify(e), index.limits);
		};
		expect(envelope(() => {})).toEqual([]);
		for (const change of [
			(e: Record<string, unknown>) => delete e.context,
			(e: Record<string, unknown>) => delete e.document,
			(e: Record<string, unknown>) => (e.context = []),
			(e: Record<string, unknown>) => (e.document = "x"),
			(e: Record<string, unknown>) => (e.critical = "context.names"),
			(e: Record<string, unknown>) => (e.critical = ["context.names", 1]),
		]) {
			expect(envelope(change), change.toString()).toEqual(["context.invalid_envelope"]);
		}
		expect(envelope(e => (e.critical = ["context.names"]))).toEqual([]);
		expect(envelope(e => (e.prefixes = 1))).toEqual([]);
		expect(envelope(e => ((e.$schema = 1), delete e.context))).toEqual(["context.undeclared_schema"]);
	});

	test("an entry that is not a canonical spelling of its table's type is context.invalid_entry", () => {
		const valid = JSON.parse(read("valid/v4-type.json")) as { context: Record<string, unknown> };
		const tables = (context: Record<string, unknown>) => {
			const e = structuredClone(valid);
			e.context = { ...e.context, ...context };
			return contextDiagnostics(JSON.stringify(e), index.limits);
		};
		for (const context of [
			{ names: [] },
			{ names: { t: "invoice-line", "1t": "x" } },
			{ names: { t: 1 } },
			{ names: { t: "invoice-Line" } },
			{ names: { t: "invoice_line" } },
			{ names: { t: "a-b" } },
			{ names: { t: "USD1" } },
			{ packagePaths: { p: "my-org//billing" } },
			{ modulePaths: { m: "S-D-K" } },
			{ fqNames: { i: "morphir/S-D-K:basics#int" } },
			{ fqNames: { i: "morphir/SDK.basics#int" } },
			{ fqNames: { i: "morphir/SDK:basics#int#x" } },
		]) {
			expect(tables(context), JSON.stringify(context)).toEqual(["context.invalid_entry"]);
		}
		for (const context of [{ names: { t: "value-in-USD" } }, { names: { t: "a" } }, { names: { t: "USD-1" } }, { packagePaths: { p: "morphir/SDK" } }, { fqNames: { i: "my-org/billing:invoicing#line-total" } }]) {
			expect(tables(context), JSON.stringify(context)).toEqual([]);
		}
		expect(canonicalSpelling("fqNames", "morphir/S-D-K:basics#int")).toBe("morphir/SDK:basics#int");
		expect(canonicalSpelling("names", "USD1")).toBe("USD-1");
		expect(tables({ names: { t: `${"x".repeat(1025)}_` } })).toEqual(["context.name_too_long"]);
	});

	test("member order and duplicate members survive parsing", () => {
		expect(parseOrdered('{"b":1,"a":[true,null],"b":"x"}')).toEqual({ members: [["b", 1], ["a", [true, null]], ["b", "x"]] });
		expect(() => parseOrdered('{"a":1,}')).toThrow("invalid JSON");
	});

	test("a twin that does not match the example is reported", () => {
		const example = parseOrdered(read("valid/v4-type.json"));
		const twin = JSON.parse(read("expanded/v4-type.json")) as { def: { TypeAliasDefinition: { typeExp: { Record: { fields: Record<string, string> } } } } };
		expect(expansionProblems(example, twin)).toEqual([]);
		twin.def.TypeAliasDefinition.typeExp.Record.fields.quantity = "morphir/SDK:basics#float";
		expect(expansionProblems(example, twin).join()).toContain("does not expand to");
	});

	test("a classic slot expands to word arrays; the checker accepts either encoding because it does not type positions", () => {
		const example = parseOrdered(read("valid/v3-type.json"));
		const twin = JSON.parse(read("expanded/v3-type.json")) as { name: unknown };
		expect(expansionProblems(example, twin)).toEqual([]);
		// The v3 tree's `name` member is a canonical string. The checker would accept arrays here too: position typing
		// is the reader's rule, which this checker does not implement (see the header of check-ir-context.ts).
		twin.name = ["invoice", "line"];
		expect(expansionProblems(example, twin)).toEqual([]);
		expect(classicName("value-in-USD")).toEqual(["value", "in", "u", "s", "d"]);
		expect(classicFqName("morphir/SDK:basics#int")).toEqual([[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]]);
	});

	test("a twin that is not a valid plain document is refused by its IR schema", () => {
		const twin = JSON.parse(read("expanded/v4-type.json")) as { name: string };
		expect(plainSchemaAccepts(root, 4, "type", twin)).toBe(true);
		twin.name = "Not-A-Name";
		expect(plainSchemaAccepts(root, 4, "type", twin)).toBe(false);
		const single = JSON.parse(read("expanded/v3-single-file.json")) as { distribution: unknown[] };
		expect(plainSchemaAccepts(root, 3, "single-file", single)).toBe(true);
		single.distribution[0] = "Librari";
		expect(plainSchemaAccepts(root, 3, "single-file", single)).toBe(false);
	}, 60_000);

	test("the envelope schema is identified by its URL and refuses an unknown table spelling", () => {
		const envelope = JSON.parse(read("valid/v4-type.json")) as { $schema: string; context: { fqNames: Record<string, string> } };
		expect(envelope.$schema).toBe(CONTEXT_SCHEMA_URL);
		expect(schemaAccepts(schema, envelope)).toBe(true);
		envelope.context.fqNames.i = "morphir/SDK.basics.int";
		expect(schemaAccepts(schema, envelope)).toBe(false);
	}, 60_000);
});
