import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { checkpointRecipe } from "../model/fixture-builders";
import corpus from "./cases.json";
import assets from "./assets.json";
import graph from "./fixtures/model.json";
import payloadIr from "./fixtures/payload-types.ir.json";

// Fixture integrity only. No trait outcomes are evaluated or generated here.
const bytes = (path: string) => readFileSync(new URL(path, import.meta.url));
const sha256 = (data: string | Uint8Array) => createHash("sha256").update(data).digest("hex");

describe("typed trait reference corpus integrity", () => {
  test("reviewed fixture bytes match the inventory", () => {
    for (const asset of assets.assets) {
      const data = bytes(asset.path);
      expect(data.byteLength).toBe(asset.bytes);
      expect(sha256(data)).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(data.toString("utf8"));
    }
  });

  test("every explicit fixture input exists in the inventory", () => {
    const paths = new Set(assets.assets.map((asset) => asset.path));
    const ids = new Set<string>();
    expect(corpus.status).toBe("reference-only");
    expect(corpus.cases.length).toBe(47);
    for (const artifact of corpus.environment.artifacts) expect(paths.has(artifact.path)).toBe(true);
    for (const item of corpus.cases) {
      expect(ids.has(item.id)).toBe(false);
      ids.add(item.id);
      expect(paths.has(item.input.graph)).toBe(true);
      if ("ionInsertions" in item.input) {
        for (const insertion of item.input.ionInsertions ?? []) expect(paths.has(insertion.asset)).toBe(true);
      }
      if ("linkedProjection" in item.input && item.input.linkedProjection) {
        expect(paths.has(item.input.linkedProjection.provider.fragment)).toBe(true);
      }
      if ("modelInputs" in item.input) {
        for (const model of item.input.modelInputs ?? []) expect(paths.has(model.path)).toBe(true);
      }
    }
  });

  test("existing M1 recipe retains trait records and exact source text in its existing owner", () => {
    const recipe = checkpointRecipe(graph, {
      unitId: "trait-model",
      packageName: payloadIr.distribution.Specs.packageName,
      modules: payloadIr.distribution.Specs.spec.modules,
    });
    expect(recipe.ir).toEqual(payloadIr);
    expect(recipe.metadata).toEqual([{ nodeId: "unit:trait-model", data: graph }]);
    expect(recipe.metadata[0]!.data.sources[0]!.fragments[0]!.text)
      .toBe("Quantity keeps its meaning before encoding is chosen.\n\n  Keep this wording.\n");
    recipe.metadata[0]!.data.traits.applications[0]!.payload = "Changed";
    expect(graph.traits.applications[0]!.payload).toBe("Quantity");
  });

  test("diagnostic pointers name authored graph data or operation input", () => {
    // Shallow list replacement is the documented fixture recipe, not validation.
    const missing: { id: string; path: string }[] = [];
    for (const item of corpus.cases) {
      const materialized = {
        ...graph,
        traits: { ...graph.traits, ...("traits" in item.input ? item.input.traits : {}) },
      };
      if (!("diagnostics" in item.expected)) continue;
      for (const diagnostic of item.expected.diagnostics ?? []) {
        const paths = [diagnostic.path];
        if ("relatedPath" in diagnostic && typeof diagnostic.relatedPath === "string") paths.push(diagnostic.relatedPath);
        for (const path of paths) {
          // Ordinary JSON object addressing; no graph/reference semantics are checked.
          const keys = path === "" ? [] : path.slice(1).split("/")
            .map((key) => key.replaceAll("~1", "/").replaceAll("~0", "~"));
          const found = [materialized, item.input].some((root) => {
            let value: unknown = root;
            for (const key of keys) {
              if (value === null || typeof value !== "object" || !Object.hasOwn(value, key)) return false;
              value = (value as Record<string, unknown>)[key];
            }
            return true;
          });
          if (!found) missing.push({ id: item.id, path });
        }
      }
    }
    expect(missing).toEqual([]);
  });

  test("the complete template head and navigable sections survive publication", () => {
    const html = bytes("contract.html").toString("utf8");
    const start = html.indexOf("\n<head>\n"), end = html.indexOf("\n</head>\n");
    expect(start).toBeGreaterThan(0);
    expect(end).toBeGreaterThan(start);
    expect(sha256(html.slice(start + 1, end + "\n</head>".length)))
      .toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    expect(rendered).toMatch(/<\/head>\s*<body>\s*<main>\s*<h1>/);
    expect(rendered).toMatch(/<\/main>\s*<\/body>\s*<\/html>\s*$/);
    const ids = [...rendered.matchAll(/<section id="([^"]+)"/g)].map((match) => match[1]);
    expect(new Set(ids).size).toBe(ids.length);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of ids) expect(toc).toContain(`href="#${id}"`);
  });
});
