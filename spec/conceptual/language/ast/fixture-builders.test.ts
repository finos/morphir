import { describe, expect, test } from "bun:test";
import { appendDeclarations, constructFragment } from "./fixture-builders";
import type { Declaration, Source, TypeExpression } from "./types";

describe("declaration fixture construction", () => {
  test("constructFragment deep-clones supplied sources and declarations", () => {
    const sources: Source[] = [{ id: "source", revision: "s1", text: "type alias A = a\n" }];
    const declarations: Declaration[] = [{
      id: "alias-a", span: { sourceId: "source", start: 0, end: 16, unit: "utf8-byte" },
      kind: "alias", name: "A", typeParameters: [],
      value: {
        id: "variable-a", span: { sourceId: "source", start: 15, end: 16, unit: "utf8-byte" },
        kind: "variable", name: "a",
      },
    }];
    const result = constructFragment(sources, declarations);
    expect(result).toEqual({ profile: "morphir-declarations/0.1.0-draft.1", sources, declarations });
    result.sources[0]!.text = "changed";
    const alias = result.declarations[0]!;
    if (alias.kind !== "alias") throw new Error("Expected authored alias");
    alias.value.span.start = 0;
    alias.typeParameters.push({
      id: "binder-a", span: { sourceId: "source", start: 0, end: 0, unit: "utf8-byte" },
      name: "a", origin: "declared",
    });
    expect(sources[0]!.text).toBe("type alias A = a\n");
    expect(declarations[0]!).toMatchObject({ typeParameters: [], value: { span: { start: 15 } } });
    sources[0]!.revision = "s2";
    declarations[0]!.name = "Renamed";
    expect(result.sources[0]!.revision).toBe("s1");
    expect(alias.name).toBe("A");
  });

  test("appendDeclarations retains order and duplicate IDs while isolating both inputs", () => {
    const span = { sourceId: "source", start: 0, end: 0, unit: "utf8-byte" } as const;
    const first: Declaration = {
      id: "same-id", span, kind: "function-spec", name: "first", typeParameters: [],
      inputs: [], output: { id: "unit-first", span, kind: "unit" },
    };
    const second: Declaration = {
      id: "same-id", span, kind: "function-spec", name: "second", typeParameters: [],
      inputs: [], output: { id: "unit-second", span, kind: "unit" },
    };
    const fragment = constructFragment([{ id: "source", revision: "s1", text: "" }], [first]);
    const additions = [second];
    const result = appendDeclarations(fragment, additions);
    expect(result.declarations).toEqual([first, second]);
    expect(result.profile).toBe(fragment.profile);
    result.sources[0]!.text = "edited";
    result.declarations[0]!.span.end = 1;
    result.declarations[1]!.name = "edited";
    result.declarations.push(first);
    expect(fragment.sources[0]!.text).toBe("");
    expect(fragment.declarations[0]!.span.end).toBe(0);
    expect(fragment.declarations).toHaveLength(1);
    expect(additions).toHaveLength(1);
    expect(second.name).toBe("second");
  });

  test("builders preserve nested duplicate unions and deliberate invalid tuple and union arities", () => {
    const span = { sourceId: "source", start: 0, end: 0, unit: "utf8-byte" } as const;
    const variable: TypeExpression = { id: "unbound", span, kind: "variable", name: "a" };
    const members: TypeExpression[] = [
      variable,
      { id: "nested", span, kind: "union", members: [variable, variable] },
      { id: "empty-union", span, kind: "union", members: [] },
      { id: "singleton-union", span, kind: "union", members: [variable] },
      { id: "empty-tuple", span, kind: "tuple", elements: [] },
      { id: "singleton-tuple", span, kind: "tuple", elements: [variable] },
      { id: "six-tuple", span, kind: "tuple", elements: [variable, variable, variable, variable, variable, variable] },
    ];
    const declaration: Declaration = {
      id: "authored", span, kind: "alias", name: "Authored", typeParameters: [],
      value: { id: "outer", span, kind: "union", members },
    };
    const fragment = constructFragment([], [declaration]);
    expect(fragment.declarations).toEqual([declaration]);
    expect(appendDeclarations(constructFragment([], []), [declaration]).declarations).toEqual([declaration]);
    const alias = fragment.declarations[0]!;
    if (alias.kind !== "alias" || alias.value.kind !== "union") throw new Error("Expected authored union alias");
    const nested = alias.value.members[1]!;
    if (nested.kind !== "union") throw new Error("Expected authored nested union");
    nested.members.push(variable);
    expect(members[1]).toMatchObject({ members: [variable, variable] });
    expect(alias.typeParameters).toEqual([]);
  });

  test("appendDeclarations retains unknown data and critical lists without interpreting them", () => {
    const source = { id: "source", revision: "s1", text: "", critical: ["future"], future: { notes: ["source"] } };
    const declaration: Declaration & { future: { notes: string[] } } = {
      id: "opaque", span: { sourceId: "source", start: 0, end: 0, unit: "utf8-byte" },
      kind: "opaque-alias", name: "Opaque", typeParameters: [], critical: ["future"],
      representation: { id: "unit", span: { sourceId: "source", start: 0, end: 0, unit: "utf8-byte" }, kind: "unit" },
      future: { notes: ["declaration"] },
    };
    const fragment = {
      ...constructFragment([source], [declaration]),
      critical: ["future"], future: { notes: ["fragment"] },
    };
    const result = appendDeclarations(fragment, []);
    expect(result).toEqual(fragment);
    fragment.future.notes.push("changed");
    source.future.notes.push("changed");
    declaration.future.notes.push("changed");
    expect(result).toMatchObject({
      critical: ["future"], future: { notes: ["fragment"] },
      sources: [{ critical: ["future"], future: { notes: ["source"] } }],
      declarations: [{ critical: ["future"], future: { notes: ["declaration"] } }],
    });
  });
});
