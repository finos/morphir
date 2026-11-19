// Tests for the MEP Smithy model check. Run with:
//   bun test tools/spec-mep-smithy.test.ts
//
// spec-mep-smithy.ts guards its CLI body behind `if (import.meta.main)`, so
// importing it here does not run the smithy CLI.
import { expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { format, parse } from "@std/semver";
import {
	canonical,
	codeDifference,
	contractDifferences,
	fences,
	findingCodes,
	gleamTypes,
	pointerValue,
	protocolExamples,
	transcriptMessages,
	uncovered,
	wireName,
} from "./spec-mep-smithy";

const draft = [
	"# Draft",
	"",
	"```text",
	"Content-Length: 60\\r\\n",
	"\\r\\n",
	'{"jsonrpc":"2.0","id":1,"method":"morphir.ping","params":{}}',
	"```",
	"",
	"```json",
	'{ "jsonrpc": "2.0", "method": "morphir.exit" }',
	"```",
	"",
	"```json",
	'{ "uri": "file:///a.elm" }',
	"```",
	"",
	"```mermaid",
	"sequenceDiagram",
	"```",
].join("\n");

test("the current protocol values are inventoried separately from historical claims", () => {
	const source = "docs/design/draft/extensions/protocol.md";
	const examples = protocolExamples(readFileSync(source, "utf8"));
	const { values } = JSON.parse(readFileSync("spec/mep/smithy/values.json", "utf8"));
	expect(uncovered(examples.values, values.filter((v: any) => v.source === source).map((v: any) => v.value))).toEqual([]);
	const current = values.find((v: any) => v.value?.$schema?.endsWith("/claims.schema.json"));
	expect(current?.memberNames).toBe("json");
	expect(values.find((v: any) => v.value?.claimsVersion)?.name).toContain("historical");
});

test("bounded-generation handshakes use exact, canonical version tokens", () => {
	type VersionTuple = { protocolVersion: string; accessVersion: string; irVersion: string };
	type Handshake = {
		params: { protocolVersions: string[]; modelAccess: { tuples: VersionTuple[] } };
	};
	const file = "spec/mep/smithy/transcripts/session-model-access.md";
	const [initialize] = transcriptMessages(readFileSync(file, "utf8")) as Handshake[];
	const [tuple] = initialize!.params.modelAccess.tuples;
	expect(initialize!.params.protocolVersions).toEqual(["0.2.0-draft.2", "0.2.0-draft.1"]);
	expect(tuple).toMatchObject({ protocolVersion: "0.2.0-draft.2", accessVersion: "0.1.0-draft.1", irVersion: "4.0.0" });
	for (const version of [tuple!.protocolVersion, tuple!.accessVersion, tuple!.irVersion]) {
		expect(format(parse(version))).toBe(version);
	}
});

test("the orders walkthrough uses checked wire frames and the frozen corpus", () => {
	const fixture = "spec/mck/bounded-generation/fixtures/acme-orders";
	const walkthrough = readFileSync("docs/spec/ir/bounded-generation.md", "utf8");
	const { messages } = protocolExamples(walkthrough);
	const transcript = transcriptMessages(readFileSync("spec/mep/smithy/transcripts/session-model-access.md", "utf8"));
	expect(messages).toHaveLength(1);
	expect(uncovered(messages, transcript)).toEqual([]);

	type Version = { singleFile: string; trees: Record<string, string> };
	const { versions } = JSON.parse(readFileSync(`${fixture}/cases.json`, "utf8")) as { versions: Version[] };
	for (const { singleFile, trees } of versions) {
		for (const path of [singleFile, ...Object.values(trees)]) {
			expect(walkthrough).toContain(`${fixture}/${path})`);
		}
	}

	type InventoryEntry = Partial<Record<"module" | "type" | "value", { documentId: string }>>;
	type Delivery = { requestId: string; kind: string; entries?: InventoryEntry[]; documentId?: string; decodedByteLength?: number; sha256?: string; content?: string };
	const frames = transcript as { params?: { deliveries?: Delivery[] } }[];
	const deliveries = frames.flatMap(frame => frame.params?.deliveries ?? []);
	const expected = JSON.parse(readFileSync(`${fixture}/expected.json`, "utf8")) as { domainInventory: { pages: string[][]; finalPageBody: { document: string } } };
	const pages = deliveries.filter(delivery => delivery.requestId === "domain-first" || delivery.requestId === "domain-second");
	expect(pages.map(page => page.entries?.map(entry => Object.keys(entry)))).toEqual([[["type"], ["value"]], [["value"]]]);
	expect(pages.map(page => page.entries?.flatMap(entry => Object.values(entry).map(payload => payload.documentId)))).toEqual(expected.domainInventory.pages);

	const documents = deliveries.filter(delivery => delivery.kind === "document");
	expect(documents.map(document => document.documentId)).toEqual([
		expected.domainInventory.finalPageBody.document,
		"pkg/acme/orders/domain/order.value",
	]);
	for (const document of documents) {
		const bytes = readFileSync(`${fixture}/v4/plain-json/${document.documentId}.json`);
		expect(document.decodedByteLength).toBe(bytes.length);
		expect(document.sha256).toBe(createHash("sha256").update(bytes).digest("hex"));
		expect(document.content).toBe(bytes.toString("base64"));
	}
});

test("the orders WASM controls pin independent outputs for literal and reference changes", () => {
	type Patch = { op: string; path: string; value: unknown };
	type ModelId = "frozen" | "literal-74" | "redirected-128";
	type Model = {
		patchDocuments?: Record<string, Patch[]>;
		addDocuments?: Record<string, unknown>;
		expect: { lastPage: string[]; referencedValue: string; artifacts: { path: string; utf8: string }[] };
	};
	const kit = "spec/mck/bounded-generation";
	const { fixture, models, cases } = JSON.parse(readFileSync(`${kit}/orders-wasm.controls.json`, "utf8")) as {
		fixture: string;
		models: Record<ModelId, Model>;
		cases: { model: ModelId; beforeValidAdvance?: { round: number; patchDelivery: Patch[]; errorCode: number } }[];
	};
	const domain = "pkg/acme/orders/domain";
	const literal = "/def/Public/ExpressionBody/body/Literal/IntegerLiteral";
	const reference = "/def/Public/ExpressionBody/body/Reference";
	const readDocument = (path: string) => JSON.parse(readFileSync(`${kit}/${fixture}/${domain}/${path}.json`, "utf8"));
	const frozenOrder = readDocument("order.value");
	expect(pointerValue(frozenOrder, literal)).toBe(73);
	expect(pointerValue(readDocument("total-in-_usd.value"), reference)).toBe("acme/orders:domain#order");

	for (const model of Object.values(models)) {
		for (const [path, patches] of Object.entries(model.patchDocuments ?? {})) {
			const document = JSON.parse(readFileSync(`${kit}/${fixture}/${path}`, "utf8"));
			for (const patch of patches.filter(patch => patch.op === "test")) {
				expect(pointerValue(document, patch.path)).toEqual(patch.value);
			}
		}
	}

	const changed = models["literal-74"];
	expect(changed.patchDocuments?.[`${domain}/order.value.json`]?.[1]).toEqual({ op: "replace", path: literal, value: 74 });
	const redirected = models["redirected-128"];
	expect(redirected.patchDocuments?.[`${domain}/module.json`]?.[1]).toEqual({ op: "add", path: "/values/1", value: "reserve" });
	expect(redirected.patchDocuments?.[`${domain}/total-in-_usd.value.json`]?.[1]).toEqual({
		op: "replace", path: reference, value: "acme/orders:domain#reserve",
	});
	expect(redirected.patchDocuments?.[`${domain}/order.value.json`]).toBeUndefined();
	expect(pointerValue(redirected.addDocuments?.[`${domain}/reserve.value.json`], literal)).toBe(128);
	expect(Object.values(models).map(({ expect: result }) => result)).toEqual([
		{ lastPage: ["total-in-_usd.value"], referencedValue: "order.value", artifacts: [{ path: "order.txt", utf8: "73\n" }] },
		{ lastPage: ["total-in-_usd.value"], referencedValue: "order.value", artifacts: [{ path: "order.txt", utf8: "74\n" }] },
		{ lastPage: ["reserve.value", "total-in-_usd.value"], referencedValue: "reserve.value", artifacts: [{ path: "order.txt", utf8: "128\n" }] },
	]);
	expect(cases.flatMap(({ model, beforeValidAdvance }) =>
		beforeValidAdvance ? [[model, beforeValidAdvance.round, beforeValidAdvance.patchDelivery[0]?.path, beforeValidAdvance.errorCode]] : [],
	)).toEqual([
		["frozen", 4, "/snapshotId", -32602],
		["frozen", 5, "/sha256", -32602],
	]);
});

test("reads fences with their info string and opening line", () => {
	expect(fences(draft).map((fence) => [fence.info, fence.line])).toEqual([
		["text", 3],
		["json", 9],
		["json", 13],
		["mermaid", 17],
	]);
});

test("a longer fence holds a shorter one", () => {
	const markdown = "````md\n```json\n{}\n```\n````\n";
	expect(fences(markdown)).toEqual([{ info: "md", line: 1, body: "```json\n{}\n```" }]);
});

test("splits protocol examples into messages and values, with framing bodies", () => {
	const { messages, values } = protocolExamples(draft);
	expect(messages.map((example) => example.line)).toEqual([6, 9]);
	expect(values).toEqual([{ line: 13, value: { uri: "file:///a.elm" } }]);
});

test("refuses a json fence that is not JSON", () => {
	expect(() => protocolExamples("```json\n{ nope\n```\n")).toThrow("is not JSON");
});

test("reads transcript messages and skips expect lists and prose fences", () => {
	const transcript = [
		"```jsonrpc host -> extension",
		'{"jsonrpc": "2.0", "method": "morphir.exit"}',
		"```",
		"```jsonrpc extension",
		'{"jsonrpc": "2.0", "id": 1, "result": {}}',
		"```",
		"```jsonrpc-expect",
		'[{"code": "StateViolation", "entry": 0}]',
		"```",
		"```json",
		"{}",
		"```",
	].join("\n");
	expect(transcriptMessages(transcript)).toEqual([
		{ jsonrpc: "2.0", method: "morphir.exit" },
		{ jsonrpc: "2.0", id: 1, result: {} },
	]);
});

test("compares values without regard to key order or whitespace, but with array order", () => {
	expect(canonical({ b: 1, a: [1, { d: 2, c: 3 }] })).toBe(canonical({ a: [1, { c: 3, d: 2 }], b: 1 }));
	expect(canonical([1, 2])).not.toBe(canonical([2, 1]));
});

test("reports the lines of examples that no known value matches", () => {
	const examples = [
		{ line: 3, value: { a: 1 } },
		{ line: 9, value: { b: 2 } },
	];
	expect(uncovered(examples, [{ a: 1 }])).toEqual([9]);
});

test("follows a JSON Pointer with escapes, and names a missing member", () => {
	const document = { source: { "a/b": { "c~d": [10, 20] } } };
	expect(pointerValue(document, "/source/a~1b/c~0d/1")).toBe(20);
	expect(pointerValue(document, "")).toBe(document);
	expect(() => pointerValue(document, "/source/missing")).toThrow("/source/missing");
});

test("reads sorted finding codes from a CLI report, and refuses other output", () => {
	const report = JSON.stringify({ valid: false, findings: [{ code: "UnknownMember" }, { code: "EnumValue" }] });
	expect(findingCodes(report)).toEqual(["EnumValue", "UnknownMember"]);
	expect(() => findingCodes("smithy: cannot infer the format")).toThrow("did not write a JSON report");
});

test("describes a difference in finding codes, in any expected order", () => {
	expect(codeDifference(["B", "A"], ["A", "B"])).toBeUndefined();
	expect(codeDifference([], ["UnknownMember"])).toBe("expected [], found [UnknownMember]");
});

const gleam = `
/// A peer. \`kind: X\` in a comment is not a field.
pub type PeerInfo {
  PeerInfo(kind: PeerKind, name: String, min_sdk_version: Option(List(String)))
}

pub type PeerKind {
  Cli
  Unspecified
}

pub type Outcome {
  Done(model: Json, diagnostics: List(String))
  Failed(diagnostics: List(String))
}
`;

test("reads Gleam types, constructors and labels, with nested type arguments", () => {
	expect(gleamTypes(gleam)).toEqual([
		{ name: "PeerInfo", constructors: [{ name: "PeerInfo", labels: ["kind", "name", "min_sdk_version"], optionalLabels: ["min_sdk_version"] }] },
		{ name: "PeerKind", constructors: [{ name: "Cli", labels: [], optionalLabels: [] }, { name: "Unspecified", labels: [], optionalLabels: [] }] },
		{
			name: "Outcome",
			constructors: [
				{ name: "Done", labels: ["model", "diagnostics"], optionalLabels: [] },
				{ name: "Failed", labels: ["diagnostics"], optionalLabels: [] },
			],
		},
	]);
});

test("turns snake_case labels into lowerCamelCase wire names", () => {
	expect(wireName("min_sdk_version")).toBe("minSdkVersion");
	expect(wireName("ir_version")).toBe("irVersion");
	expect(wireName("name")).toBe("name");
});

const shapes = {
	"demo#PeerInfo": { type: "structure", members: { kind: {}, name: {}, minSdkVersion: {} } },
	"demo#PeerKind": { type: "enum", members: { CLI: {}, UNSPECIFIED: {} } },
	"demo#Outcome": { type: "structure", members: { success: {}, model: {}, diagnostics: {} } },
};

test("agrees when fields, enum members and a tagged sum match", () => {
	const exceptions = { Outcome: { tag: "success", reason: "tagged" } };
	expect(contractDifferences(gleamTypes(gleam), shapes, "demo", exceptions)).toEqual([]);
});

test("names each difference, and a sum type with no mapping", () => {
	const changed = {
		...shapes,
		"demo#PeerInfo": { type: "structure", members: { kind: {}, name: {}, workspace: {} } },
		"demo#PeerKind": { type: "enum", members: { CLI: {} } },
	};
	expect(contractDifferences(gleamTypes(gleam), changed, "demo", {})).toEqual([
		"PeerInfo: the structure has no member minSdkVersion",
		"PeerInfo: the contract has no field workspace",
		"PeerKind: 2 constructors, but 1 enum members",
		"Outcome: a sum type with no listed mapping",
	]);
});

test("applies exceptions for snake_case, missing and added members", () => {
	const exceptions = {
		PeerInfo: { snakeCase: true, missing: ["kind"], added: ["extra"], reason: "test" },
		Outcome: { tag: "success", reason: "tagged" },
	};
	const changed = { ...shapes, "demo#PeerInfo": { type: "structure", members: { name: {}, min_sdk_version: {}, extra: {} } } };
	expect(contractDifferences(gleamTypes(gleam), changed, "demo", exceptions)).toEqual([]);
});

test("compares each member-tagged union variant with its Gleam constructor", () => {
	const required = { traits: { "smithy.api#required": {} } };
	const source = `
pub type Entry {
  ModuleEntry(document_id: String, member_selection: Option(String))
  TypeEntry(document_id: String, name: String)
}
`;
	const entries = gleamTypes(source);
	const unionShapes = {
		"demo#Entry": {
			type: "union",
			members: { module: { target: "demo#ModuleEntry" }, type: { target: "demo#TypeEntry" } },
		},
		"demo#ModuleEntry": { type: "structure", members: { documentId: required, memberSelection: {} } },
		"demo#TypeEntry": { type: "structure", members: { documentId: required, name: required } },
	};
	const exceptions = { Entry: { union: { ModuleEntry: "module", TypeEntry: "type" }, reason: "member-tagged" } };
	expect(contractDifferences(entries, unionShapes, "demo", exceptions)).toEqual([]);

	const swappedFields = {
		...unionShapes,
		"demo#TypeEntry": { type: "structure", members: { documentId: required, memberSelection: {} } },
	};
	expect(contractDifferences(entries, swappedFields, "demo", exceptions)).toEqual([
		"Entry.type: the structure has no member name",
		"Entry.type: the contract has no field memberSelection",
	]);

	const optionalName = {
		...unionShapes,
		"demo#TypeEntry": { type: "structure", members: { documentId: required, name: {} } },
	};
	expect(contractDifferences(entries, optionalName, "demo", exceptions)).toEqual([
		"Entry.type.name: Smithy member must be required to match Gleam",
	]);
	const optionalInGleam = gleamTypes(source.replace("name: String", "name: Option(String)"));
	expect(contractDifferences(optionalInGleam, unionShapes, "demo", exceptions)).toEqual([
		"Entry.type.name: Smithy member must be optional to match Gleam",
	]);
});
