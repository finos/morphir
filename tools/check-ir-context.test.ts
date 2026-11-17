// The fixed examples of the Morphir file context, and the checks behind tools/check-ir-context.ts.
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";

import {
	CONTEXT_SCHEMA_URL,
	EXAMPLES_DIR,
	type ExampleIndex,
	classicFqName,
	classicName,
	contextDiagnostics,
	exampleProblems,
	expansionProblems,
	parseOrdered,
	plainSchemaAccepts,
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
		expect(refusals).toEqual(["context.after_document", "context.duplicate_entry", "context.name_too_long", "context.too_many_entries", "context.undeclared_schema", "context.unknown_alias", "context.unknown_critical"]);
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

describe("the checker can fail", () => {
	test("a plain document has no context diagnostics", () => {
		expect(contextDiagnostics(read("expanded/v4-type.json"), index.limits)).toEqual([]);
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
