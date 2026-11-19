import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  bindReferenceIndex,
  buildReferenceIndex,
  dictionaryCandidates,
  type ReferenceSource,
} from "./indexed-access-index";
import type { OccurrenceIdentity } from "./indexed-access-scan";

const root = path.resolve(import.meta.dir, "../spec/experiments/indexed-access");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");
const controls = JSON.parse(read("controls.json")) as {
  id: string;
  documents: { document: string; file: string }[];
}[];
const queries = JSON.parse(read("queries.json")) as { id: string; fqName: string }[];
const expected = JSON.parse(read("expected.json")) as Record<string, OccurrenceIdentity[]>;
const sources = (control: typeof controls[number]): ReferenceSource[] =>
  control.documents.map(({ document, file }) => ({ document, bytes: Buffer.from(read(file)) }));
const sorted = (items: readonly OccurrenceIdentity[]) => items.map(item => JSON.stringify(item)).sort();

for (const control of controls) {
  test(`${control.id}: persisted index matches the frozen occurrences`, () => {
    const documents = sources(control);
    const index = JSON.parse(JSON.stringify(buildReferenceIndex(documents))) as ReturnType<typeof buildReferenceIndex>;
    const lookup = bindReferenceIndex(index, documents);

    for (const { id, fqName } of queries) {
      const found = lookup(fqName);
      expect(sorted(found.occurrences)).toEqual(sorted(expected[id]!));
      expect(found.decodedValues).toBe(found.occurrences.length);
      expect(found.sourceBytes).toBeLessThan(documents.reduce((total, file) => total + file.bytes.byteLength, 0));
    }
  });
}

test("offsets from another encoding or field order cannot bind to the rewritten sources", () => {
  const [contextual, ...rewrites] = controls;
  const index = buildReferenceIndex(sources(contextual!));

  for (const rewrite of rewrites) {
    expect(() => bindReferenceIndex(index, sources(rewrite))).toThrow(/changed source/);
  }

  const byName = sources(contextual!);
  const a = byName[0]!;
  const sameSize = Buffer.from(a.bytes.toString().replace('"$name":"i"', '"$name":"u"'));
  expect(sameSize.byteLength).toBe(a.bytes.byteLength);
  expect(() => bindReferenceIndex(index, [{ ...a, bytes: sameSize }, byName[1]!])).toThrow(/changed source/);
  expect(() => bindReferenceIndex(index, [a])).toThrow(/document set/);
});

test("UTF-8 offsets isolate the selected spelling and the checked snapshot owns its bytes", () => {
  const [initial, second] = sources(controls[0]!);
  const first = {
    document: initial!.document,
    bytes: Buffer.from(initial!.bytes.toString().replace('"access":"Public"', '"doc":"π🙂","access":"Public"')),
  };
  const documents = [first, second!];
  const index = buildReferenceIndex(documents);
  const spans = index.documents[0]!.entries.filter(entry => entry.fqName === queries[0]!.fqName);
  expect(spans.map(({ offset, length }) => first.bytes.subarray(offset, offset + length).toString()))
    .toEqual(['{"$name":"i"}', '{"$name":"i"}']);

  const lookup = bindReferenceIndex(index, documents);
  first.bytes.fill(0);
  const result = lookup(queries[0]!.fqName);
  expect(sorted(result.occurrences)).toEqual(sorted(expected.int!));
  expect(result.sourceBytes).toBe(2 * Buffer.byteLength('{"$name":"i"}') + Buffer.byteLength('"morphir/SDK:basics#int"'));
});

test("dictionary-only lookup misses fully spelled values and finds an unused alias definition", () => {
  const candidates = dictionaryCandidates(sources(controls[0]!));
  expect(candidates(queries.find(query => query.id === "add")!.fqName)).toEqual([]);
  expect(candidates(queries.find(query => query.id === "unused")!.fqName))
    .toEqual([controls[0]!.documents[0]!.document]);
});
