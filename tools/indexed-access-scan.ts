// Experiment-only plain full scan. No index, MCK execution or resource claims.
import { CONTEXT_SCHEMA_URL, isSpelling, parseOrdered, type Ordered } from "./check-ir-context";
import { field, object, referenceSlots, type ReferenceSlot } from "./ir-reference-slots";

export type SourceDocument = Readonly<{ document: string; text: string }>;
export type OccurrenceIdentity = Readonly<{ document: string; location: string; slot: ReferenceSlot }>;

export function scanReferences(documents: readonly SourceDocument[], fqName: string): OccurrenceIdentity[] {
  if (!isSpelling("fqNames", fqName)) throw new Error("Expected a canonical FQName query");
  if (new Set(documents.map(d => d.document)).size !== documents.length) throw new Error("Duplicate physical document identity");
  return documents.flatMap(source => {
    const root = parseOrdered(source.text);
    const schema = object(root).members.find(([key]) => key === "$schema")?.[1];
    let document: Ordered = root;
    const fqNames = new Map<string, string>();
    if (schema !== undefined) {
      if (schema !== CONTEXT_SCHEMA_URL) throw new Error("Unsupported contextual schema");
      // A complete read makes context order irrelevant. No streaming/bounded claim.
      const context = object(field(root, "context"));
      const table = context.members.find(([key]) => key === "fqNames")?.[1];
      if (table !== undefined) for (const [id, spelling] of object(table).members) {
        if (!/^[A-Za-z][A-Za-z0-9]*$/.test(id) || typeof spelling !== "string" || !isSpelling("fqNames", spelling)) throw new Error("Invalid FQName table entry");
        fqNames.set(id, spelling);
      }
      document = field(root, "document");
    }
    return referenceSlots(document, fqNames)
      .filter(occurrence => occurrence.fqName === fqName)
      .map(({ location, slot }) => ({ document: source.document, location, slot }));
  });
}
