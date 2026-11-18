// The fixed examples of the Morphir file context, and the checks behind tools/check-ir-context.ts.
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import { isMap, isScalar, isSeq, parseDocument } from "yaml";

import {
	CONTEXT_SCHEMA_URL,
	EXAMPLES_DIR,
	type ExampleIndex,
	classicFqName,
	classicName,
	contextDiagnostics,
	exampleProblems,
	expansionProblems,
	isOrderCarrying,
	isSpelling,
	jcs,
	jcsProblem,
	Lexeme,
	type Ordered,
	parseOrdered,
	plain,
	plainSchemaAccepts,
	plainSchemaAcceptsText,
	POLICY_DIR,
	type PolicyIndex,
	policyFormProblem,
	policyProblems,
	schemaAccepts,
} from "./check-ir-context";

const root = path.resolve(import.meta.dir, "..");
const examples = path.join(root, EXAMPLES_DIR);
const read = (file: string) => readFileSync(path.join(examples, file), "utf8");
const index = JSON.parse(read("cases.json")) as ExampleIndex;
const schema = path.join(root, index.schema);

function parseOrderedYaml(text: string): Ordered {
	const document = parseDocument(text);
	expect(document.errors).toEqual([]);

	function value(node: unknown): Ordered {
		if (node === null) return null;
		if (isMap(node)) {
			return { members: node.items.map(({ key, value: child }) => {
				if (!isScalar(key) || typeof key.value !== "string") throw new Error("Expected a string YAML key");
				return [key.value, value(child)];
			}) };
		}
		if (isSeq(node)) return node.items.map(value);
		if (isScalar(node)) {
			const scalar = node.value;
			if (scalar === null || typeof scalar === "boolean" || typeof scalar === "string") return scalar;
			if (typeof scalar === "number" && node.range) {
				return new Lexeme(text.slice(node.range[0], node.range[1]));
			}
		}
		throw new Error("Expected an explicit YAML value");
	}

	return value(document.contents);
}

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

	test("every valid example has an explicit YAML spelling of the same contextual envelope", () => {
		for (const c of index.cases.filter(c => c.expected === "valid")) {
			const yaml = parseOrderedYaml(read(c.file.replace(/\.json$/, ".yaml")));
			expect(yaml, c.id).toEqual(parseOrdered(read(c.file), { lexemes: true }));
			expect(schemaAccepts(schema, plain(yaml)), c.id).toBe(true);
		}
	}, 60_000);

	test("a YAML twin may not spell an integer format version as a float", () => {
		const json = read("valid/v4-type.json");
		const yaml = read("valid/v4-type.yaml");
		const changed = yaml.replace("formatVersion: 4", "formatVersion: 4.0");
		expect(parseOrderedYaml(changed)).not.toEqual(parseOrdered(json, { lexemes: true }));
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

	test("every expected file is in the written form and has the form its row says, and every input is a valid plain document", () => {
		expect(policyProblems(root)).toEqual([]);
	}, 180_000);

	test("the cases cover each file kind at v3 and v4 and each policy rule", () => {
		const ids = policy.cases.map(c => c.id).sort();
		expect(ids).toEqual([
			"alias-allocation-order", "exact-numbers", "look-alike-literal", "loss", "loss-boundary-accepted", "loss-boundary-declined",
			"name-used-once", "non-ascii-content", "ordered-inputs", "table-order", "tie",
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

	test("the order-carrying objects are the v4 body inputTypes and value specification inputs, and IR 3 has none", () => {
		for (const body of ["ExpressionBody", "NativeBody", "ExternalBody", "IncompleteBody"]) expect(isOrderCarrying(4, ["def", body, "inputTypes"]), body).toBe(true);
		expect(isOrderCarrying(4, ["values", "total", "ExpressionBody", "inputTypes"])).toBe(true);
		expect(isOrderCarrying(4, ["spec", "inputs"])).toBe(true);
		expect(isOrderCarrying(4, ["values", "total", "inputs"])).toBe(true);
		expect(isOrderCarrying(4, ["values", "total", "value", "inputs"])).toBe(true);
		// A record's fields, a module's values, a field that happens to be named inputs, and JSON inside a literal are not.
		expect(isOrderCarrying(4, ["def", "TypeAliasDefinition", "typeExp", "Record", "fields"])).toBe(false);
		expect(isOrderCarrying(4, ["values"])).toBe(false);
		expect(isOrderCarrying(4, ["def", "TypeAliasDefinition", "typeExp", "Record", "fields", "inputs"])).toBe(false);
		expect(isOrderCarrying(4, ["def", "ExpressionBody", "body", "Literal", "DocumentLiteral", "ExpressionBody", "inputTypes"])).toBe(false);
		expect(isOrderCarrying(3, ["def", "value", "value", "inputTypes"])).toBe(false);
	});

	test("the written form keeps the input's parameter order and sorts every other object", () => {
		const policyDir = path.join(root, POLICY_DIR, "cases/ordered-inputs");
		const bytes = readFileSync(path.join(policyDir, "expected.json"));
		const source = parseOrdered(readFileSync(path.join(policyDir, "input.json"), "utf8"), { lexemes: true });
		expect(policyFormProblem(bytes, 4, source)).toBeUndefined();
		// The same file is not JCS, and the JCS-sorted parameters are not the policy's form of this input.
		expect(jcsProblem(bytes)).toBeDefined();
		const text = new TextDecoder().decode(bytes);
		const sorted = text.replace('"rate":{"$name":"a"},"amount":{"$name":"b"},"discount":{"$name":"a"},"limit":{"$name":"b"}', '"amount":{"$name":"b"},"discount":{"$name":"a"},"limit":{"$name":"b"},"rate":{"$name":"a"}');
		expect(sorted).not.toBe(text);
		expect(policyFormProblem(new TextEncoder().encode(sorted), 4, source)).toBeDefined();
		// Outside the order-carrying object, document order is not kept: an unsorted def is refused.
		const unsortedDef = text.replace(',"access":"Public"}', "}").replace('{"def":{"ExpressionBody"', '{"def":{"access":"Public","ExpressionBody"');
		expect(unsortedDef).not.toBe(text);
		expect(policyFormProblem(new TextEncoder().encode(unsortedDef), 4, source)).toBeDefined();
		// In IR 3 every object is sorted.
		expect(policyFormProblem(new TextEncoder().encode('{"inputTypes":{"b":1,"a":2}}'), 3)).toBeDefined();
		expect(policyFormProblem(new TextEncoder().encode('{"def":{"ExpressionBody":{"inputTypes":{"b":1,"a":2}}}}'), 4)).toBeUndefined();
	});

	describe("the written form keeps every number lexeme and DocumentLiteral content as input.json writes them", () => {
		const caseDir = path.join(root, POLICY_DIR, "cases/exact-numbers");
		const inputText = readFileSync(path.join(caseDir, "input.json"), "utf8");
		const source = parseOrdered(inputText, { lexemes: true });
		const text = readFileSync(path.join(caseDir, "expected.json"), "utf8");
		const problem = (t: string, ir = 4, from: typeof source = source) => policyFormProblem(new TextEncoder().encode(t), ir, from);
		const sourceless = (t: string, ir: number) => policyFormProblem(new TextEncoder().encode(t), ir);
		const changed = (from: string, to: string) => {
			expect(text.includes(from), from).toBe(true);
			return text.replace(from, to);
		};

		test("exact-numbers is in the written form, and is not JCS", () => {
			expect(problem(text)).toBeUndefined();
			expect(jcsProblem(new TextEncoder().encode(text))).toBeDefined();
			// JCS would round the integer, drop the fractions and expand the exponents, and sort the literal's members.
			const asJcs = jcs(parseOrdered(text, { lexemes: true }));
			expect(asJcs).toContain('"IntegerLiteral":9007199254740992');
			expect(asJcs).toContain('"FloatLiteral":1}');
			expect(asJcs).toContain('"FloatLiteral":100}');
			expect(asJcs).toContain('{"cap":1.5,"region":"outside-primary","tiers":[{"rate":0.1,"upTo":1000}]}');
			expect(problem(asJcs)).toBeDefined();
		});

		test("a number spelled otherwise than in input.json is refused, even when its value is the same", () => {
			for (const [from, to] of [
				["9007199254740993", "9007199254740992"],
				['"FloatLiteral":1.0}', '"FloatLiteral":1}'],
				['"FloatLiteral":1.0}', '"FloatLiteral":1.00}'],
				['"FloatLiteral":1e2}', '"FloatLiteral":100}'],
				['"FloatLiteral":1e2}', '"FloatLiteral":1E2}'],
				['"cap":1.50', '"cap":1.5'],
				['"upTo":1e3', '"upTo":1000'],
				['"rate":0.10', '"rate":0.1'],
				['"formatVersion":4', '"formatVersion":4.0'],
			]) {
				expect(problem(changed(from!, to!)), `${from} -> ${to}`).toBeDefined();
			}
		});

		test("DocumentLiteral content keeps the input's member order at every depth; other objects are still sorted", () => {
			expect(problem(changed('{"region":"outside-primary","cap":1.50,', '{"cap":1.50,"region":"outside-primary",'))).toBeDefined();
			expect(problem(changed('{"upTo":1e3,"rate":0.10}', '{"rate":0.10,"upTo":1e3}'))).toBeDefined();
			// The wrapper around the literal is sorted as before: its one member cannot be out of order, but body is.
			expect(problem(changed('{"def":{"ExpressionBody"', '{"def":{"access":"Public","ExpressionBody"').replace(',"access":"Public"}', "}"))).toBeDefined();
			// Escaping and whitespace rules still hold inside the literal.
			expect(problem(changed('"region":"outside-primary"', '"region": "outside-primary"'))).toBeDefined();
			expect(problem(changed('"region":"outside-primary"', '"region":"outside\\u002dprimary"'))).toBeDefined();
		});

		test("without a source each number and literal object keeps its own form; IR 3 has no DocumentLiteral", () => {
			const literal = '{"Literal":{"DocumentLiteral":{"b":1.0,"a":[{"d":1e2,"c":-0}]}}}';
			expect(sourceless(literal, 4)).toBeUndefined();
			expect(sourceless(literal, 3)).toBeDefined();
			expect(sourceless('{"a":{"DocumentLiteral":{"a":1,"b":2}}}', 3)).toBeUndefined();
			// A number where the source has none, and a source parsed without lexemes, are reported.
			expect(problem('{"a":1}', 4, parseOrdered('{"a":"1"}', { lexemes: true }))).toContain("no number at /a");
			expect(problem('{"a":1}', 4, parseOrdered('{"a":1}'))).toContain("parsed with lexemes");
		});

		test("the input's own text is what the plain schema validates", () => {
			expect(plainSchemaAcceptsText(root, 4, "value", inputText)).toBe(true);
			expect(plainSchemaAcceptsText(root, 4, "value", inputText.replace('"name": "limits"', '"name": "Limits"'))).toBe(false);
		}, 60_000);
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

	test("an entry that is not a spelling of its table's type is context.invalid_entry", () => {
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
			{ packagePaths: { p: "my-org//billing" } },
			{ modulePaths: { m: "Basics" } },
			{ fqNames: { i: "morphir/Sdk:basics#int" } },
			{ fqNames: { i: "morphir/SDK.basics#int" } },
			{ fqNames: { i: "morphir/SDK:basics#int#x" } },
		]) {
			expect(tables(context), JSON.stringify(context)).toEqual(["context.invalid_entry"]);
		}
		// Each segment is written as it is read, so these are canonical: `a-b` is two words, `USD1` one initialism,
		// and `morphir/S-D-K` a package of three one-letter initialisms, a different path from `morphir/SDK`.
		for (const context of [
			{ names: { t: "value-in-USD" } },
			{ names: { t: "a" } },
			{ names: { t: "a-b" } },
			{ names: { t: "USD1" } },
			{ names: { t: "USD-1" } },
			{ packagePaths: { p: "morphir/SDK" } },
			{ modulePaths: { m: "S-D-K" } },
			{ fqNames: { i: "morphir/S-D-K:basics#int" } },
			{ fqNames: { i: "my-org/billing:invoicing#line-total" } },
		]) {
			expect(tables(context), JSON.stringify(context)).toEqual([]);
		}
		expect(isSpelling("fqNames", "morphir/S-D-K:basics#int")).toBe(true);
		expect(isSpelling("fqNames", "morphir/Sdk:basics#int")).toBe(false);
		expect(tables({ names: { t: `${"x".repeat(1025)}_` } })).toEqual(["context.name_too_long"]);
	});

	test("table spellings are judged by the naming conformance fixture's segment grammar", () => {
		const naming = JSON.parse(readFileSync(path.join(root, "docs/spec/ir/fixtures/naming-conformance.json"), "utf8")) as {
			roundTripCases: { canonical: { uppercase: string } }[];
			pathCases: { canonical: { uppercase: string } }[];
			fqNameCases: { canonical: { uppercase: string } }[];
			rejectCases: { input: string; validAs: { uppercase: boolean } }[];
		};
		const valid = JSON.parse(read("valid/v4-type.json")) as { context: Record<string, unknown> };
		const entry = (table: string, spelling: string) => {
			const e = structuredClone(valid);
			e.context = { ...e.context, [table]: { ...(e.context[table] as Record<string, string> | undefined), fixture: spelling } };
			return contextDiagnostics(JSON.stringify(e), index.limits);
		};
		const verdicts: string[] = [];
		const expectVerdict = (table: string, spelling: string, expected: string[]) => {
			const got = entry(table, spelling);
			if (!Bun.deepEquals(got, expected)) verdicts.push(`${table} ${spelling}: [${got}], expected [${expected}]`);
		};
		for (const c of naming.roundTripCases) expectVerdict("names", c.canonical.uppercase, []);
		for (const c of naming.pathCases) for (const t of ["packagePaths", "modulePaths"]) expectVerdict(t, c.canonical.uppercase, []);
		for (const c of naming.fqNameCases) expectVerdict("fqNames", c.canonical.uppercase, []);
		// The fixture's FQName cases hold no digit initialism, so its paths and names are also combined into FQNames.
		for (const p of naming.pathCases) for (const n of naming.roundTripCases) expectVerdict("fqNames", `${p.canonical.uppercase}:${p.canonical.uppercase}#${n.canonical.uppercase}`, []);
		for (const c of naming.rejectCases) if (!c.validAs.uppercase) expectVerdict("names", c.input, ["context.invalid_entry"]);
		expect(verdicts).toEqual([]);
	});

	test("member order and duplicate members survive parsing", () => {
		expect(parseOrdered('{"b":1,"a":[true,null],"b":"x"}')).toEqual({ members: [["b", 1], ["a", [true, null]], ["b", "x"]] });
		expect(() => parseOrdered('{"a":1,}')).toThrow("invalid JSON");
		expect(parseOrdered("[1.0,1e2,9007199254740993]", { lexemes: true })).toEqual([new Lexeme("1.0"), new Lexeme("1e2"), new Lexeme("9007199254740993")]);
		expect(parseOrdered("[1.0,1e2]")).toEqual([1, 100]);
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
