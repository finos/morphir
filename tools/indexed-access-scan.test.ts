import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import { scanReferences } from "./indexed-access-scan";

const root = path.resolve(import.meta.dir, "../spec/experiments/indexed-access");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");
const queries = JSON.parse(read("queries.json")) as { id: string; fqName: string }[];
const expected = JSON.parse(read("expected.json"));
const controls = JSON.parse(read("controls.json")) as { id: string; documents: { document: string; file: string }[] }[];
const a = "pkg/lab/probe/a.value.json";
const b = "pkg/lab/probe/b.value.json";
const key = (v: unknown) => JSON.stringify(v);
const sorted = (vs: unknown[]) => vs.map(key).sort();

for (const control of controls) {
  test(`${control.id}: full scan matches independently frozen occurrence sets`, () => {
    const documents = control.documents.map(({ document, file }) => ({ document, text: read(file) }));
    for (const query of queries) {
      expect(sorted(scanReferences(documents, query.fqName)), query.id).toEqual(sorted(expected[query.id]));
    }
  });
}

test("changed encoding changes bytes while preserving physical identity and every semantic occurrence", () => {
  expect(read("fixtures/contextual.json")).not.toBe(read("fixtures/expanded.json"));
  for (const query of queries) {
    const frozen = expected[query.id].filter((o: { document: string }) => o.document === a);
    for (const variant of ["contextual", "expanded"]) {
      expect(sorted(scanReferences([{ document: a, text: read(`fixtures/${variant}.json`) }], query.fqName))).toEqual(sorted(frozen));
    }
  }
});

test("the experiment refuses unsupported shapes rather than reporting incomplete success", () => {
  expect(() => scanReferences([{ document: a, text: '{"formatVersion":3}' }], queries[0]!.fqName)).toThrow();
  const changed = read("fixtures/spelled.json").replace('"Reference"', '"UnknownValue"');
  expect(() => scanReferences([{ document: b, text: changed }], queries[0]!.fqName)).toThrow();
});
