import { createHash } from "node:crypto";
import { isSpelling, parseOrdered } from "./check-ir-context";
import { readReferenceDocument, type OccurrenceIdentity } from "./indexed-access-scan";
import { referenceSlots, resolveReferenceName, type ReferenceSlot } from "./ir-reference-slots";

export type ReferenceSource = Readonly<{ document: string; bytes: Uint8Array }>;
type IndexEntry = Readonly<{
  location: string;
  slot: ReferenceSlot;
  fqName: string;
  offset: number;
  length: number;
}>;
export type ReferenceIndex = Readonly<{
  documents: ReadonlyArray<Readonly<{
    document: string;
    sha256: string;
    sourceBytes: number;
    names: ReadonlyArray<readonly [string, string]>;
    entries: readonly IndexEntry[];
  }>>;
}>;
type LookupResult = Readonly<{
  occurrences: readonly OccurrenceIdentity[];
  sourceBytes: number;
  decodedValues: number;
}>;

const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const digest = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

function checkQuery(fqName: string): void {
  if (!isSpelling("fqNames", fqName)) throw new Error("Expected a canonical FQName query");
}

/** Build from complete source bytes. The typed walker selects reference spans after parsing. */
export function buildReferenceIndex(sources: readonly ReferenceSource[]): ReferenceIndex {
  if (new Set(sources.map(source => source.document)).size !== sources.length) throw new Error("Duplicate physical document identity");
  return {
    documents: sources.map(({ document, bytes }) => {
      const text = utf8.decode(bytes);
      const spans = new Map<string, { start: number; end: number }>();
      const root = parseOrdered(text, {
        onValueSpan(pointer, start, end) { spans.set(pointer, { start, end }); },
      });
      const parsed = readReferenceDocument(root);
      const ranges = referenceSlots(parsed.document, parsed.fqNames).map(({ spellingLocation, ...occurrence }) => {
        const pointer = parsed.pointerPrefix + spellingLocation;
        const span = spans.get(pointer);
        if (!span) throw new Error(`No source span for ${pointer}`);
        return { ...occurrence, ...span };
      }).sort((a, b) => a.start - b.start);

      let previousEnd = 0;
      let previousByteEnd = 0;
      const entries = ranges.map(({ start, end, ...occurrence }) => {
        const offset = previousByteEnd + Buffer.byteLength(text.slice(previousEnd, start));
        const length = Buffer.byteLength(text.slice(start, end));
        previousEnd = end;
        previousByteEnd = offset + length;
        return { ...occurrence, offset, length };
      });
      return { document, sha256: digest(bytes), sourceBytes: bytes.byteLength, names: [...parsed.fqNames], entries };
    }),
  };
}

/** Bind an index produced by this experiment to privately retained, verified source bytes. */
export function bindReferenceIndex(index: ReferenceIndex, sources: readonly ReferenceSource[]): (fqName: string) => LookupResult {
  const byDocument = new Map(sources.map(source => [source.document, source.bytes]));
  const identifiers = new Set(index.documents.map(file => file.document));
  if (identifiers.size !== index.documents.length || byDocument.size !== sources.length
      || byDocument.size !== identifiers.size || [...identifiers].some(id => !byDocument.has(id))) {
    throw new Error("Index document set differs from the supplied sources");
  }

  const byName = new Map<string, {
    document: string;
    bytes: Uint8Array;
    names: ReadonlyMap<string, string>;
    entry: IndexEntry;
  }[]>();
  for (const file of index.documents) {
    const bytes = Uint8Array.from(byDocument.get(file.document)!);
    if (bytes.byteLength !== file.sourceBytes || digest(bytes) !== file.sha256) {
      throw new Error(`Index cannot bind changed source ${file.document}`);
    }
    const names = new Map(file.names);
    for (const entry of file.entries) {
      if (!Number.isSafeInteger(entry.offset) || entry.offset < 0 || !Number.isSafeInteger(entry.length)
          || entry.length <= 0 || entry.offset + entry.length > bytes.byteLength) {
        throw new Error(`Index span exceeds ${file.document}`);
      }
      const candidates = byName.get(entry.fqName) ?? [];
      candidates.push({ document: file.document, bytes, names, entry: { ...entry } });
      byName.set(entry.fqName, candidates);
    }
  }

  return fqName => {
    checkQuery(fqName);
    let sourceBytes = 0;
    const candidates = byName.get(fqName) ?? [];
    const occurrences = candidates.map(({ document, bytes, names, entry }) => {
      const { offset, length, location, slot } = entry;
      const parsed = parseOrdered(utf8.decode(bytes.subarray(offset, offset + length)));
      if (resolveReferenceName(parsed, names, location) !== fqName) {
        throw new Error(`Index spelling differs at ${document}${location}`);
      }
      sourceBytes += length;
      return { document, location, slot };
    });
    return { occurrences, sourceBytes, decodedValues: occurrences.length };
  };
}

/** List documents with a matching alias declaration. This supplies no typed occurrence identity. */
export function dictionaryCandidates(sources: readonly ReferenceSource[]): (fqName: string) => string[] {
  const dictionaries = sources.map(({ document, bytes }) => ({
    document,
    spellings: new Set(readReferenceDocument(parseOrdered(utf8.decode(bytes))).fqNames.values()),
  }));
  return fqName => {
    checkQuery(fqName);
    return dictionaries.filter(({ spellings }) => spellings.has(fqName)).map(({ document }) => document);
  };
}
