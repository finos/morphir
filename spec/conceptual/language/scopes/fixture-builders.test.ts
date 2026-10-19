import { describe, expect, test } from "bun:test";
import { appendRecords, constructInput } from "./fixture-builders";
import type { Dependency, ModelBinding, Region, ScopeImport, ScopeInput, ScopeReference, ScopeSymbol } from "./types";

describe("scope fixture construction", () => {
  test("constructInput deep-clones supplied context, source bytes and L1 fragments", () => {
    const metadata = { notes: ["retain"] };
    const authored: Omit<ScopeInput, "profile" | "declarationProfile"> = {
      context: {
        unitId: "unit", packageName: "example/build", sourceSet: ["source"],
        model: { id: "model", revision: "m1", metadata },
      },
      dependencies: [],
      modelBindings: [],
      typeEnvironment: { namedTypes: [{ id: "int", path: ["Int"], arity: 0, visibility: "public" }] },
      sources: [{ id: "source", revision: "s1", text: "// π\r\n" }],
      fragments: [{
        id: "fragment",
        fragment: {
          profile: "morphir-declarations/0.1.0-draft.1",
          sources: [{ id: "source", revision: "s1", text: "// π\r\n" }], declarations: [],
        },
      }],
      regions: [], symbols: [], imports: [], references: [],
    };
    const result = constructInput(authored);
    expect(result).toEqual({
      ...authored,
      profile: "morphir-scopes/0.1.0-draft.1",
      declarationProfile: "morphir-declarations/0.1.0-draft.1",
    });
    result.sources[0]!.text = "changed";
    result.fragments[0]!.fragment.sources[0]!.revision = "s2";
    result.context.model.metadata = { notes: ["changed"] };
    result.typeEnvironment.namedTypes[0]!.path.push("changed");
    expect(authored.sources[0]!.text).toBe("// π\r\n");
    expect(authored.fragments[0]!.fragment.sources[0]!.revision).toBe("s1");
    expect(authored.context.model.metadata).toEqual({ notes: ["retain"] });
    expect(authored.typeEnvironment.namedTypes[0]!.path).toEqual(["Int"]);
    const cloned = constructInput(authored);
    metadata.notes.push("author edit");
    expect(cloned.context.model.metadata).toEqual({ notes: ["retain"] });
    authored.context.model.revision = "m2";
    expect(result.context.model.revision).toBe("m1");
  });

  test("appendRecords preserves duplicate records and authored invalid names, spans and binders", () => {
    const span = { sourceId: "missing", start: -1, end: 2, unit: "utf8-byte" } as const;
    const source = { id: "duplicate", revision: "s1", text: "// π 😀\r\n" };
    const dependency: Dependency = {
      slot: "sdk", resolvedNodeId: "snapshot:sdk", packageName: "morphir/SDK", revision: "r1",
      exportTable: [{ path: "public-list", moduleName: "list" }, { path: "public-list", moduleName: "other" }],
      symbols: [],
    };
    const region: Region = {
      id: "module", sourceId: "missing", span, kind: "module", form: "header", parentId: "absent", name: [],
      entries: [{ kind: "reference", id: "reference" }, { kind: "import", id: "import" }],
      exports: [{ kind: "type", name: "Type" }, { kind: "type", name: "Type" }],
    };
    const symbol: ScopeSymbol = {
      id: "symbol", moduleRegionId: "module", name: "Authored_Name", canonicalName: "author-supplied-name",
      category: "constructor", ownerTypeId: "missing-type",
      declaration: { fragmentId: "fragment", nodeId: "constructor-child" },
      links: [{ kind: "contract", id: "contract", revision: "c1" }],
      provenance: [{ sourceId: "missing", revision: "s1" }],
    };
    const imported: ScopeImport = {
      id: "import", regionId: "module", span,
      target: { kind: "dependency", slot: "absent-slot", exportPath: "public-list", authoredPath: ["List"] },
      mode: { kind: "selected", selectors: [{ kind: "constructor", typeName: "Type", name: "Type" }] },
    };
    const reference: ScopeReference = {
      id: "reference", regionId: "module", span, path: ["unsupported", "long", "path"], category: "value",
      localBinders: [{ id: "binder", name: "a", category: "value" }, { id: "binder", name: "a", category: "value" }],
    };
    const fragment: ScopeInput["fragments"][number] = {
      id: "fragment", fragment: { profile: "morphir-declarations/0.1.0-draft.1", sources: [], declarations: [] },
    };
    const input = constructInput({
      context: {
        unitId: "unit", packageName: "example/build", sourceSet: [],
        model: { id: "model", revision: "m1", metadata: {} },
      },
      sources: [source], dependencies: [], modelBindings: [], typeEnvironment: { namedTypes: [] }, fragments: [], regions: [], symbols: [], imports: [], references: [],
    });
    const additions = {
      sources: [source, source], dependencies: [dependency, dependency], fragments: [fragment, fragment],
      regions: [region, region], symbols: [symbol, symbol], imports: [imported, imported], references: [reference, reference],
    };
    const result = appendRecords(input, additions);
    expect(result).toEqual({ ...input, ...additions, sources: [source, source, source] });
    expect(result.context.sourceSet).toEqual([]);
    result.sources[0]!.text = "changed existing";
    result.sources[1]!.text = "changed added";
    result.references[0]!.localBinders[0]!.name = "changed";
    result.references[0]!.span.start = 0;
    result.dependencies[0]!.exportTable[0]!.moduleName = "changed";
    result.fragments[0]!.fragment.sources.push(source);
    expect(input.sources[0]!.text).toBe("// π 😀\r\n");
    expect(source.text).toBe("// π 😀\r\n");
    expect(reference.localBinders[0]!.name).toBe("a");
    expect(span.start).toBe(-1);
    expect(dependency.exportTable[0]!.moduleName).toBe("list");
    expect(fragment.fragment.sources).toEqual([]);
  });

  test("model bindings remain supplied snapshots when cloned and appended, including conflicts", () => {
    const metadata = { title: "Original", notes: ["retained"] };
    const binding: ModelBinding = {
      regionId: "model-region",
      model: { id: "model", revision: "m1", qualifiedName: ["Finos", "Rules"], metadata },
    };
    const conflicting: ModelBinding = {
      regionId: "model-region",
      model: { id: "other-model", revision: "m2", qualifiedName: ["Finos", "Rules"], metadata: { title: "Conflicting" } },
    };
    const input = constructInput({
      context: {
        unitId: "unit", packageName: "example/build", sourceSet: [],
        model: { id: "model", revision: "m1", metadata },
      },
      modelBindings: [binding], typeEnvironment: { namedTypes: [] }, sources: [], dependencies: [], fragments: [], regions: [], symbols: [], imports: [], references: [],
    });
    const result = appendRecords(input, { modelBindings: [conflicting, binding] });
    expect(result.modelBindings).toEqual([binding, conflicting, binding]);
    expect(result.context.model).toEqual(input.context.model);
    metadata.notes.push("author edit");
    expect(input.modelBindings[0]!.model.metadata).toEqual({ title: "Original", notes: ["retained"] });
    result.modelBindings[0]!.model.revision = "changed";
    result.modelBindings[1]!.model.metadata = {};
    expect(input.modelBindings[0]!.model.revision).toBe("m1");
    expect(conflicting.model.metadata).toEqual({ title: "Conflicting" });
    expect(binding.model.revision).toBe("m1");
  });
});
