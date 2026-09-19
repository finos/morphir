// Tests for the generated-schema drift check. Run with:
//   bun test tools/check-schemas-generated.test.ts
//
// check-schemas-generated.ts guards its CLI body behind `if (import.meta.main)`,
// so importing it here does not regenerate anything.
import { expect, test } from "bun:test";
import { schemaDrift } from "./check-schemas-generated";

const snapshot = (entries: Record<string, string>) => new Map(Object.entries(entries));

test("reports nothing when regeneration leaves every file as it was", () => {
	const files = snapshot({ "a.json": "{}\n", "b.json": "[]\n" });
	expect(schemaDrift(files, snapshot({ "a.json": "{}\n", "b.json": "[]\n" }))).toEqual([]);
});

test("reports a file whose regenerated content differs", () => {
	const before = snapshot({ "a.json": '{"description":"old"}\n' });
	const after = snapshot({ "a.json": '{"description":"new"}\n' });
	expect(schemaDrift(before, after)).toEqual([{ file: "a.json", change: "changed" }]);
});

test("ignores a line-ending difference alone", () => {
	const before = snapshot({ "a.json": "{\r\n}\r\n" });
	const after = snapshot({ "a.json": "{\n}\n" });
	expect(schemaDrift(before, after)).toEqual([]);
});

test("reports a file the generator adds or no longer produces", () => {
	const before = snapshot({ "gone.json": "{}\n" });
	const after = snapshot({ "new.json": "{}\n" });
	expect(schemaDrift(before, after)).toEqual([
		{ file: "gone.json", change: "removed" },
		{ file: "new.json", change: "added" },
	]);
});
