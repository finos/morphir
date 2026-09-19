// Tests for the coverage-vocabulary renderer. Run with:
//   bun test tools/gen-mck-vocabulary.test.ts
//
// The generator guards its CLI body behind `if (import.meta.main)`, so this
// import neither reads the TypeScript workspace nor writes anything.
import { expect, test } from "bun:test";
import { renderVocabulary } from "./gen-mck-vocabulary";

const tables = {
	nodes: ["Type", "IRFile"],
	aliases: { Distribution: "IRFile" },
	entries: [{ node: "Type", variant: "Record", members: [{ name: "fields", spelling: "canonical" as const }, { name: "attrs", spelling: "legacy" as const }] }],
};

test("renders tab-indented JSON with a trailing newline and a version", () => {
	const text = renderVocabulary(tables);
	expect(text.endsWith("}\n")).toBe(true);
	expect(text).toContain('\n\t"vocabularyVersion": 1,');
	const parsed = JSON.parse(text);
	expect(parsed.irVersion).toBe(4);
	expect(parsed.nodes).toEqual(["Type", "IRFile"]);
	expect(parsed.aliases).toEqual({ Distribution: "IRFile" });
	expect(parsed.entries[0].members.map((m: { name: string }) => m.name)).toEqual(["fields", "attrs"]);
});

test("keeps entry order and drops fields the schema does not know", () => {
	const extra = { ...tables, entries: [{ ...tables.entries[0], extra: true } as never] };
	expect(Object.keys(JSON.parse(renderVocabulary(extra)).entries[0])).toEqual(["node", "variant", "members"]);
});

test("refuses an entry or alias naming an unknown node kind", () => {
	expect(() => renderVocabulary({ ...tables, entries: [{ node: "Nope", variant: "X", members: [] }] })).toThrow(/unknown node kinds: Nope/);
	expect(() => renderVocabulary({ ...tables, aliases: { Old: "Nope" } })).toThrow(/alias Old names unknown node kind Nope/);
});
