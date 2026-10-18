import { describe, expect, test } from "bun:test";
import { appendRecords, checkpointRecipe } from "./fixture-builders";

// These checks exercise fixture construction only. They do not evaluate a graph.
const authored = {
  recordVersion: "0.1.0-draft.1",
  profile: "morphir-conceptual/0.1.0-draft.1",
  model: { id: "urn:example:model", revision: "m1" },
  sources: [],
  entities: [{ id: "urn:example:concept", content: { text: "Borrower" } }],
  relationships: [],
  capabilities: [],
};

describe("fixture builders", () => {
  test("appending preserves deliberate duplicate inputs and isolates nested records", () => {
    const extra = { id: "urn:example:concept", content: { text: "Another meaning" } };
    const result = appendRecords(authored, { entities: [extra] });
    expect(result.entities).toEqual([
      { id: "urn:example:concept", content: { text: "Borrower" } },
      { id: "urn:example:concept", content: { text: "Another meaning" } },
    ]);
    result.entities[0]!.content.text = "changed";
    result.entities[1]!.content.text = "also changed";
    expect(authored.entities[0]!.content.text).toBe("Borrower");
    expect(extra.content.text).toBe("Another meaning");
  });

  test("checkpoint recipe uses the explicit unit owner and build package", () => {
    const result = checkpointRecipe(authored, {
      unitId: "fixture-unit",
      packageName: "example/explicit-package",
      modules: {},
    });
    expect(result).toEqual({
      unitId: "fixture-unit",
      ir: {
        formatVersion: 4,
        distribution: { Specs: {
          packageName: "example/explicit-package",
          dependencies: {},
          spec: { modules: {} },
        } },
      },
      metadata: [{ nodeId: "unit:fixture-unit", data: authored }],
      annotations: ["morphir_pipeline"],
      provenance: [],
    });
  });

  test("checkpoint retains supplied signatures, dependency closure and provenance without inference", () => {
    const modules = { api: { values: { identity: { inputs: { value: "a" }, output: "a" } } } };
    const dependencies = { "example/types": { modules: {} } };
    const provenance = [{ author: "fixture-author", revision: "source-1" }];
    const result = checkpointRecipe(authored, {
      unitId: "mixed", packageName: "example/build", modules, dependencies, provenance,
    });
    expect(result.ir.distribution.Specs.spec.modules).toEqual({
      api: { values: { identity: { inputs: { value: "a" }, output: "a" } } },
    });
    expect(result.ir.distribution.Specs.dependencies).toEqual({ "example/types": { modules: {} } });
    expect(result.provenance).toEqual([{ author: "fixture-author", revision: "source-1" }]);
    result.ir.distribution.Specs.spec.modules.api.values.identity.output = "broken";
    result.provenance[0]!.author = "changed";
    result.metadata[0]!.data.entities[0]!.content.text = "lost";
    expect(modules.api.values.identity.output).toBe("a");
    expect(provenance[0]!.author).toBe("fixture-author");
    expect(authored.entities[0]!.content.text).toBe("Borrower");
  });
});

// Inventory and IR recipe assertions never compare semantic observations to an evaluator.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import assets from "./assets.json";
import corpus from "./cases.json";
import prose from "./fixtures/prose-only.json";
import mixed from "./fixtures/mixed.json";
import proseIr from "./fixtures/prose-only.ir.json";
import mixedIr from "./fixtures/mixed.ir.json";

const assetBytes = (path: string) => readFileSync(new URL(path, import.meta.url));

describe("authored corpus integrity", () => {
  test("referenced assets match their reviewed byte lengths and digests", () => {
    for (const asset of assets.assets) {
      const bytes = assetBytes(asset.path);
      expect(bytes.length).toBe(asset.bytes);
      expect(createHash("sha256").update(bytes).digest("hex")).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(bytes.toString("utf8"));
    }
  });

  test("every case input and expected IR artifact exists in the asset manifest", () => {
    const paths = new Set(assets.assets.map((asset) => asset.path));
    const ids = new Set<string>();
    for (const item of corpus.cases) {
      expect(ids.has(item.id)).toBe(false);
      ids.add(item.id);
      expect(paths.has(item.input.graph)).toBe(true);
      if ("ir" in item.input && item.input.ir) expect(paths.has(item.input.ir)).toBe(true);
      if ("implementationInputs" in item.input && item.input.implementationInputs) {
        for (const artifact of item.input.implementationInputs) expect(paths.has(artifact.path)).toBe(true);
      }
      if ("ionInsertions" in item.input && item.input.ionInsertions) {
        for (const insertion of item.input.ionInsertions) expect(paths.has(insertion.asset)).toBe(true);
      }
      if ("ir" in item.expected && item.expected.ir) expect(paths.has(item.expected.ir)).toBe(true);
    }
  });

  test("prose recipe matches an independently authored empty Specs carrier", () => {
    const recipe = checkpointRecipe(prose, {
      unitId: "prose", packageName: "example/prose", modules: {},
    });
    expect(recipe.ir).toEqual(proseIr);
    expect(recipe.metadata[0]!.nodeId).toBe("unit:prose");
    expect(recipe.metadata[0]!.data.sources[0]!.fragments[0]!.text)
      .toBe("Track what borrowers still owe.\n\n  Retain the loan identity.\n");
  });

  test("mixed recipe preserves supplied public signatures and leaves conceptual entities in metadata", () => {
    const recipe = checkpointRecipe(mixed, {
      unitId: "mixed", packageName: "example/model",
      modules: { api: { types: {}, values: { identity: { inputs: { value: "a" }, output: "a" } } } },
    });
    expect(recipe.ir).toEqual(mixedIr);
    expect(recipe.metadata[0]!.data).toEqual(mixed);
    expect(recipe.metadata[0]!.nodeId).toBe("unit:mixed");
  });
});

describe("review document integrity", () => {
  test("the complete pinned template head survives before the rendered document body", () => {
    const html = assetBytes("contract.html").toString("utf8");
    const headStart = html.indexOf("\n<head>\n");
    const headEnd = html.indexOf("\n</head>\n");
    expect(headStart).toBeGreaterThan(0);
    expect(headEnd).toBeGreaterThan(headStart);
    const head = html.slice(headStart + 1, headEnd + "\n</head>".length);
    expect(createHash("sha256").update(head).digest("hex"))
      .toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    // A literal <main> in a template comment must never become the splice point.
    expect(html.match(/<!--/g)?.length).toBe(html.match(/-->/g)?.length);
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    expect(rendered).toMatch(/<\/head>\s*<body>\s*<main>\s*<h1>/);
    expect(rendered).toMatch(/<\/main>\s*<\/body>\s*<\/html>\s*$/);
    const sectionIds = [...rendered.matchAll(/<section id="([^"]+)"/g)].map((match) => match[1]);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of sectionIds) expect(toc).toContain(`href="#${id}"`);
  });
});

// JSON Pointer existence checks address fixture data; they do not judge graph semantics.
function pointerExists(value: unknown, pointer: string): boolean {
  if (pointer === "") return true;
  if (!pointer.startsWith("/") || /~(?:[^01]|$)/.test(pointer)) return false;
  let current = value;
  for (const part of pointer.slice(1).split("/")) {
    const key = part.replaceAll("~1", "/").replaceAll("~0", "~");
    if (current === null || typeof current !== "object" || !Object.hasOwn(current, key)) return false;
    current = (current as Record<string, unknown>)[key];
  }
  return true;
}

describe("reference observation integrity", () => {
  test("diagnostic pointers select materialized graph records or operation inputs", () => {
    const missing: { case: string; path: string }[] = [];
    for (const item of corpus.cases) {
      const source = JSON.parse(assetBytes(item.input.graph).toString("utf8")) as {
        sources: unknown[]; entities: unknown[]; relationships: unknown[]; capabilities: unknown[];
      };
      const graph = appendRecords(source, "additions" in item.input ? item.input.additions ?? {} : {});
      if (!("diagnostics" in item.expected) || !item.expected.diagnostics) continue;
      for (const diagnostic of item.expected.diagnostics) {
        if (!pointerExists(graph, diagnostic.path) && !pointerExists(item.input, diagnostic.path)) missing.push({ case: item.id, path: diagnostic.path });
        if ("relatedPath" in diagnostic && typeof diagnostic.relatedPath === "string") {
          expect(pointerExists(graph, diagnostic.relatedPath) || pointerExists(item.input, diagnostic.relatedPath)).toBe(true);
        }
      }
    }
    expect(missing).toEqual([]);
  });

  test("a supplied binding expectation includes the exact artifact as a case input", () => {
    for (const item of corpus.cases) {
      if (!("implementationBinding" in item.expected) || item.expected.implementationBinding !== "supplied") continue;
      const graph = JSON.parse(assetBytes(item.input.graph).toString("utf8")) as {
        entities: { kind: string; content: { artifact?: { id: string; revision: string }; availability?: string } }[];
      };
      const artifacts = "implementationInputs" in item.input ? item.input.implementationInputs ?? [] : [];
      for (const entity of graph.entities) {
        if (entity.kind !== "implementation" || entity.content.availability !== "supplied") continue;
        expect({ case: item.id, explicitInput: artifacts.some((artifact) => artifact.id === entity.content.artifact?.id && artifact.revision === entity.content.artifact?.revision) })
          .toEqual({ case: item.id, explicitInput: true });
      }
    }
  });
});
