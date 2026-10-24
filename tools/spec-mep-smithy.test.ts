// Tests for the MEP Smithy model check. Run with:
//   bun test tools/spec-mep-smithy.test.ts
//
// spec-mep-smithy.ts guards its CLI body behind `if (import.meta.main)`, so
// importing it here does not run the smithy CLI.
import { expect, test } from "bun:test";
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
		{ name: "PeerInfo", constructors: [{ name: "PeerInfo", labels: ["kind", "name", "min_sdk_version"] }] },
		{ name: "PeerKind", constructors: [{ name: "Cli", labels: [] }, { name: "Unspecified", labels: [] }] },
		{
			name: "Outcome",
			constructors: [
				{ name: "Done", labels: ["model", "diagnostics"] },
				{ name: "Failed", labels: ["diagnostics"] },
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
