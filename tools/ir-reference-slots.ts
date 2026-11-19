// Typed traversal for the small IDX-1 controls, not a general IR reader.
// Reuses the umbrella's ordered JSON and contextual spelling API. Unsupported
// IR nodes fail closed so this experiment cannot silently claim completeness.
import { isSpelling, type Ordered, referenceId } from "./check-ir-context";

export type ReferenceSlot = "type-reference" | "value-reference";
export type ReferenceOccurrence = Readonly<{ location: string; slot: ReferenceSlot; fqName: string }>;
type ObjectValue = { members: [string, Ordered][] };

export function object(value: Ordered | undefined): ObjectValue {
  if (typeof value !== "object" || value === null || !("members" in value)) throw new Error("Expected an object in IDX-1 control");
  if (new Set(value.members.map(([key]) => key)).size !== value.members.length) throw new Error("Duplicate object member");
  return value;
}
export function field(value: Ordered, key: string): Ordered {
  const found = object(value).members.find(([name]) => name === key);
  if (!found) throw new Error(`Missing ${key}`);
  return found[1];
}
const pointer = (key: string) => key.replaceAll("~", "~0").replaceAll("/", "~1");

/** Visits only typed reference slots in the explicitly supported v4 control grammar. */
export function referenceSlots(document: Ordered, fqNames: ReadonlyMap<string, string>): ReferenceOccurrence[] {
  if (field(document, "formatVersion") !== 4) throw new Error("IDX-1 controls support only v4 value files");
  const name = field(document, "name");
  if (typeof name !== "string" || !isSpelling("names", name)) throw new Error("Invalid control name");
  const def = field(document, "def");
  const body = field(def, "ExpressionBody");
  const out: ReferenceOccurrence[] = [];
  const emit = (value: Ordered, location: string, slot: ReferenceSlot) => {
    const id = referenceId(value);
    const fqName = id === undefined ? value : fqNames.get(id);
    if (typeof fqName !== "string" || !isSpelling("fqNames", fqName)) throw new Error(`Invalid or unresolved FQName at ${location}`);
    out.push({ location, slot, fqName });
  };
  const type = (value: Ordered, location: string): void => {
    if (typeof value === "string" || referenceId(value) !== undefined) return emit(value, location, "type-reference");
    const members = object(value).members;
    if (members.length !== 1 || members[0]![0] !== "Reference") throw new Error(`Unsupported control type at ${location}`);
    emit(members[0]![1], location, "type-reference");
  };
  const expression = (value: Ordered, location: string): void => {
    if (typeof value === "string") return emit(value, location, "value-reference");
    const members = object(value).members;
    if (members.length !== 1) throw new Error(`Unsupported control value at ${location}`);
    const [tag, payload] = members[0]!;
    switch (tag) {
      case "Reference": return emit(payload, location, "value-reference");
      case "List":
        if (!Array.isArray(payload)) throw new Error("Expected List items");
        payload.forEach((item, i) => expression(item, `${location}/List/${i}`));
        return;
      case "Literal": {
        const literal = object(payload).members;
        if (literal.length !== 1) throw new Error("Expected one literal variant");
        const [kind, content] = literal[0]!;
        if (kind === "DocumentLiteral") return; // Arbitrary JSON is opaque, even convincing IR objects.
        if (kind === "StringLiteral" && typeof content === "string") return;
        throw new Error("Unsupported control literal");
      }
      default: throw new Error(`Unsupported control value ${tag} at ${location}`);
    }
  };
  const base = "/def/ExpressionBody";
  for (const [name, value] of object(field(body, "inputTypes")).members) type(value, `${base}/inputTypes/${pointer(name)}`);
  type(field(body, "outputType"), `${base}/outputType`);
  expression(field(body, "body"), `${base}/body`);
  return out;
}
