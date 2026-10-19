import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";

// Integrity of authored reference data, not scope resolution or a compatibility runner.
const bytes = (path: string) => readFileSync(new URL(path, import.meta.url));
const json = (path: string): any => JSON.parse(bytes(path).toString("utf8"));
const digest = (value: string | Uint8Array) => createHash("sha256").update(value).digest("hex");

function pointerExists(value: unknown, pointer: string): boolean {
  if (pointer === "") return true;
  if (!pointer.startsWith("/") || /~(?:[^01]|$)/.test(pointer)) return false;
  let current = value;
  for (const part of pointer.slice(1).split("/")) {
    const key = part.replaceAll("~1", "/").replaceAll("~0", "~");
    if (!current || typeof current !== "object" || !Object.hasOwn(current, key)) return false;
    current = (current as Record<string, unknown>)[key];
  }
  return true;
}

function checkSpan(span: any, sources: Map<string, string>, label: string): void {
  const text = sources.get(span.sourceId);
  expect(text, label).toBeDefined();
  const data = Buffer.from(text!);
  expect(span.unit, label).toBe("utf8-byte");
  expect(Number.isInteger(span.start) && Number.isInteger(span.end), label).toBe(true);
  expect(span.start, label).toBeGreaterThanOrEqual(0);
  expect(span.end, label).toBeGreaterThanOrEqual(span.start);
  expect(span.end, label).toBeLessThanOrEqual(data.length);
  for (const offset of [span.start, span.end]) {
    expect(offset === data.length || (data[offset]! & 0xc0) !== 0x80, `${label}: byte ${offset}`).toBe(true);
  }
}

function visitNodes(value: unknown, visit: (node: any) => void): void {
  if (!value || typeof value !== "object") return;
  const record = value as Record<string, unknown>;
  if ("span" in record) visit(record);
  for (const child of Object.values(record)) visitNodes(child, visit);
}

describe("scope reference corpus", () => {
  test("the corpus names its exact profile and independent reference status", () => {
    const corpus = json("cases.json");
    expect(corpus.profile).toBe("morphir-scopes/0.1.0-draft.1");
    expect(corpus.status).toBe("reference-only");
  });

  test("named type context is explicit and matches the pinned fixture environment", () => {
    const environment = json("env.json");
    expect(Array.isArray(environment.namedTypes)).toBe(true);
    for (const type of environment.namedTypes) {
      expect(typeof type.id).toBe("string");
      expect(type.id.length).toBeGreaterThan(0);
      expect(Array.isArray(type.path)).toBe(true);
      expect(type.path.length).toBeGreaterThan(0);
      for (const part of type.path) {
        expect(typeof part).toBe("string");
        expect(part.length).toBeGreaterThan(0);
      }
      expect(Number.isInteger(type.arity)).toBe(true);
      expect(type.arity).toBeGreaterThanOrEqual(0);
      expect(["public", "private"]).toContain(type.visibility);
    }
    for (const item of json("cases.json").cases) {
      if (!item.input.facts || (item.stage === "structure" && item.expected.outcome === "rejected")) continue;
      expect(json(item.input.facts).typeEnvironment, item.id).toEqual(environment);
    }
  });

  test("syntax expectations contain parse records without semantic scope enrichment", () => {
    for (const item of json("cases.json").cases) {
      if (item.stage !== "syntax") continue;
      expect(Object.keys(item.input), item.id).toEqual(["sources"]);
      expect(item.input.facts, item.id).toBeUndefined();
      expect(item.expected.facts, item.id).toBeUndefined();
      if (item.expected.outcome !== "accepted") {
        expect(item.expected.syntax, item.id).toBeUndefined();
        continue;
      }
      expect(item.expected.syntax, item.id).toBeDefined();
      const syntax = json(item.expected.syntax);
      expect(Object.keys(syntax).sort(), item.id).toEqual(["profile", "sources", "regions", "fragments", "imports", "declarations"].sort());
      expect(String(syntax.profile), item.id).toBe("morphir-scopes/0.1.0-draft.1");
      for (const source of item.input.sources) {
        const text = bytes(source.asset).toString("utf8");
        expect(syntax.sources.some((record: any) => record.id === source.id && record.revision === source.revision && record.text === text), `${item.id}: ${source.asset}`).toBe(true);
      }
      expect(syntax.sources.length, item.id).toBe(item.input.sources.length);
      const sources = new Map<string, string>(syntax.sources.map((source: any) => [source.id, source.text]));
      const regions = new Set<string>(syntax.regions.map((region: any) => region.id));
      const imports = new Set<string>(syntax.imports.map((record: any) => record.id));
      const declarations = new Set<string>(syntax.declarations.map((record: any) => record.nodeId));
      const fragments = new Map<string, Map<string, any>>();
      for (const entry of syntax.fragments) {
        const nodes = new Map<string, any>();
        for (const source of entry.fragment.sources) {
          expect(syntax.sources.some((record: any) => record.id === source.id && record.revision === source.revision && record.text === source.text), `${item.id}: ${entry.id}: ${source.id}`).toBe(true);
        }
        visitNodes(entry.fragment.declarations, node => {
          nodes.set(node.id, node);
          checkSpan(node.span, sources, `${item.id}: ${entry.id}: ${node.id}`);
        });
        fragments.set(entry.id, nodes);
      }
      for (const region of syntax.regions) {
        checkSpan(region.span, sources, `${item.id}: ${region.id}`);
        if (region.parentId !== undefined) expect(regions.has(region.parentId), item.id).toBe(true);
        for (const entry of region.entries) {
          expect(["region", "import", "declaration"], item.id).toContain(entry.kind);
          const ids = entry.kind === "region" ? regions : entry.kind === "import" ? imports : declarations;
          expect(ids.has(entry.id), `${item.id}: ${region.id}: ${entry.id}`).toBe(true);
        }
      }
      for (const imported of syntax.imports) {
        checkSpan(imported.span, sources, `${item.id}: ${imported.id}`);
        expect(regions.has(imported.regionId), item.id).toBe(true);
      }
      for (const declaration of syntax.declarations) {
        const keys = ["category", "moduleRegionId", "fragmentId", "nodeId"];
        if (declaration.category === "constructor") keys.push("ownerNodeId");
        expect(Object.keys(declaration).sort(), item.id).toEqual(keys.sort());
        expect(["type", "value", "constructor"], item.id).toContain(declaration.category);
        expect(regions.has(declaration.moduleRegionId), item.id).toBe(true);
        const nodes = fragments.get(declaration.fragmentId);
        expect(nodes?.has(declaration.nodeId), `${item.id}: ${declaration.nodeId}`).toBe(true);
        if (declaration.category === "constructor") {
          const owner = nodes?.get(declaration.ownerNodeId);
          expect(owner?.constructors?.some((node: any) => node.id === declaration.nodeId), `${item.id}: ${declaration.ownerNodeId}`).toBe(true);
        }
      }
    }
  });

  test("reviewed asset bytes and every referenced fixture are pinned", () => {
    const manifest = json("assets.json");
    expect(manifest.profile).toBe("morphir-scopes/0.1.0-draft.1");
    const paths = new Set<string>();
    for (const asset of manifest.assets) {
      expect(paths.has(asset.path), asset.path).toBe(false);
      paths.add(asset.path);
      const data = bytes(asset.path);
      expect(data.length, asset.path).toBe(asset.bytes);
      expect(digest(data), asset.path).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(data.toString("utf8"));
    }
    for (const path of ["cases.json", "contract.html", "grammar.ebnf", "types.ts", "fixture-builders.ts", "env.json", "sources/.gitattributes"]) {
      expect(paths.has(path), path).toBe(true);
    }
    for (const item of json("cases.json").cases) {
      for (const path of [item.input.facts, item.expected.syntax, item.expected.observation, ...item.input.sources.map((source: any) => source.asset)].filter(Boolean)) {
        expect(paths.has(path), `${item.id}: ${path}`).toBe(true);
      }
    }
    const fixtures = readdirSync(new URL("fixtures/", import.meta.url)).map(name => `fixtures/${name}`).sort();
    expect([...paths].filter(path => path.startsWith("fixtures/")).sort()).toEqual(fixtures);
  });

  test("all source assets use .mfs and match the manifest and case inventory", () => {
    const actual = readdirSync(new URL("sources/", import.meta.url))
      .filter(name => name !== ".gitattributes").map(name => `sources/${name}`).sort();
    expect(actual.length).toBeGreaterThan(0);
    for (const path of actual) expect(path.endsWith(".mfs"), path).toBe(true);
    const inventoried = json("assets.json").assets.map((asset: any) => String(asset.path))
      .filter((path: string) => path.startsWith("sources/") && path !== "sources/.gitattributes").sort();
    expect(inventoried).toEqual(actual);
    const referenced = [...new Set<string>(json("cases.json").cases
      .flatMap((item: any) => item.input.sources.map((source: any) => source.asset)))].sort();
    expect(referenced).toEqual(actual);
  });

  test("case identities, stages, coverage and structure expectations are explicit", () => {
    const corpus = json("cases.json");
    const ids = new Set<string>();
    for (const item of corpus.cases) {
      expect(typeof item.id).toBe("string");
      expect(item.id.length).toBeGreaterThan(0);
      expect(ids.has(item.id), item.id).toBe(false);
      ids.add(item.id);
      expect(["syntax", "structure", "scope", "visibility", "capability"], item.id).toContain(item.stage);
      expect(["accepted", "resolved", "rejected", "unsupported"], item.id).toContain(item.expected.outcome);
      if (item.stage === "syntax") {
        expect(item.input.facts, item.id).toBeUndefined();
        if (item.expected.outcome === "accepted") expect(item.expected.syntax, item.id).toBeDefined();
        else expect(item.expected.syntax, item.id).toBeUndefined();
      } else if (["accepted", "resolved"].includes(item.expected.outcome)) {
        expect(item.expected.observation, item.id).toBeDefined();
      }
    }
    for (const [requirement, cases] of Object.entries(corpus.coverage) as [string, string[]][]) {
      expect(cases.length, requirement).toBeGreaterThan(0);
      for (const id of cases) expect(ids.has(id), `${requirement}: ${id}`).toBe(true);
    }
    const structure = corpus.cases.filter((item: any) => item.stage === "structure");
    expect(structure.some((item: any) => item.expected.outcome === "accepted")).toBe(true);
    expect(structure.some((item: any) => item.expected.outcome === "rejected")).toBe(true);
    for (const item of structure) expect(item.input.facts, item.id).toBeDefined();
  });

  test("supplied source identities, revisions and text match the materialized facts", () => {
    for (const item of json("cases.json").cases) {
      const factsPath = item.input.facts;
      if (!factsPath) continue;
      const facts = json(factsPath);
      for (const source of item.input.sources) {
        const text = bytes(source.asset).toString("utf8");
        expect(facts.sources.some((record: any) => record.id === source.id && record.revision === source.revision && record.text === text), `${item.id}: ${source.asset}`).toBe(true);
      }
      for (const entry of facts.fragments ?? []) {
        for (const source of entry.fragment.sources ?? []) {
          expect(facts.sources.some((record: any) => record.id === source.id && record.revision === source.revision && record.text === source.text), `${item.id}: ${entry.id}: ${source.id}`).toBe(true);
        }
      }
    }
  });

  test("nonmalformed facts retain usable UTF-8 spans and explicit record references", () => {
    for (const item of json("cases.json").cases) {
      const factsPath = item.input.facts;
      if (!factsPath || (item.stage === "structure" && item.expected.outcome === "rejected")) continue;
      const facts = json(factsPath);
      const sources = new Map<string, string>(facts.sources.map((source: any) => [source.id, source.text]));
      const regions = new Map<string, any>(facts.regions.map((region: any) => [region.id, region]));
      const tables: Record<string, Set<string>> = {};
      for (const [kind, records] of Object.entries({ region: facts.regions, import: facts.imports, symbol: facts.symbols, reference: facts.references }) as [string, any[]][]) {
        tables[kind] = new Set(records.map(record => record.id));
      }
      const fragmentNodes = new Map<string, Set<string>>();
      for (const entry of facts.fragments) {
        const ids = new Set<string>();
        visitNodes(entry.fragment.declarations, node => {
          ids.add(node.id);
          checkSpan(node.span, sources, `${item.id}: ${entry.id}: ${node.id}`);
        });
        fragmentNodes.set(entry.id, ids);
      }
      for (const region of facts.regions) {
        checkSpan(region.span, sources, `${item.id}: ${region.id}`);
        if (region.parentId !== undefined) expect(regions.has(region.parentId), `${item.id}: ${region.id}`).toBe(true);
        for (const entry of region.entries) expect(tables[entry.kind]?.has(entry.id), `${item.id}: ${region.id}: ${entry.kind}/${entry.id}`).toBe(true);
      }
      for (const record of [...facts.imports, ...facts.references]) {
        checkSpan(record.span, sources, `${item.id}: ${record.id}`);
        expect(regions.has(record.regionId), `${item.id}: ${record.id}`).toBe(true);
      }
      for (const symbol of facts.symbols) {
        expect(regions.has(symbol.moduleRegionId), `${item.id}: ${symbol.id}`).toBe(true);
        expect(fragmentNodes.get(symbol.declaration.fragmentId)?.has(symbol.declaration.nodeId), `${item.id}: ${symbol.id}`).toBe(true);
      }
      for (const binding of facts.modelBindings) expect(regions.has(binding.regionId), `${item.id}: model binding`).toBe(true);
    }
  });

  test("diagnostic pointers and source spans select existing supplied locations", () => {
    for (const item of json("cases.json").cases) {
      const factsPath = item.input.facts;
      const facts = factsPath ? json(factsPath) : undefined;
      const sources = new Map<string, string>(item.input.sources.map((source: any) => [source.id, bytes(source.asset).toString("utf8")]));
      for (const diagnostic of item.expected.diagnostics ?? []) {
        expect(diagnostic.code.length, item.id).toBeGreaterThan(0);
        for (const path of [diagnostic.path, ...(diagnostic.relatedPaths ?? [])].filter((value: unknown) => value !== undefined)) {
          if (typeof path !== "string") throw new Error(`${item.id}: diagnostic pointer is not a string`);
          expect(pointerExists(facts, path) || pointerExists(item.input, path), `${item.id}: ${path}`).toBe(true);
        }
        if (diagnostic.span) checkSpan(diagnostic.span, sources, `${item.id}: ${diagnostic.code}`);
      }
    }
  });

  test("authored positive observations name supplied symbols or local binders", () => {
    for (const item of json("cases.json").cases) {
      if (!item.expected.observation) continue;
      const observed = json(item.expected.observation);
      const facts = json(item.input.facts);
      expect(observed.outcome, item.id).toBe(item.expected.outcome);
      expect(observed.model, item.id).toEqual(facts.context.model);
      for (const module of observed.modules) {
        for (const id of module.symbolIds) expect(facts.symbols.some((symbol: any) => symbol.id === id), `${item.id}: ${id}`).toBe(true);
      }
      for (const reference of observed.references) {
        const probe = facts.references.find((record: any) => record.id === reference.referenceId);
        expect(probe, `${item.id}: ${reference.referenceId}`).toBeDefined();
        const target = reference.target;
        if (target.kind === "binder") {
          const binder = probe.localBinders.find((record: any) => record.id === target.binderId);
          expect(binder, `${item.id}: ${target.binderId}`).toBeDefined();
          expect(target.name).toBe(binder.name);
          expect(target.category).toBe(binder.category);
          continue;
        }
        expect(String(target.kind), item.id).toBe("symbol");
        let symbol: any;
        if (target.binding.kind === "unit") {
          expect(target.binding.unitId).toBe(facts.context.unitId);
          expect(target.packageName).toBe(facts.context.packageName);
          symbol = facts.symbols.find((record: any) => record.id === target.symbolId);
        } else {
          expect(target.binding.kind).toBe("dependency");
          const dependency = facts.dependencies.find((record: any) => record.slot === target.binding.slot && record.resolvedNodeId === target.binding.resolvedNodeId && record.revision === target.binding.revision);
          expect(dependency, `${item.id}: ${target.binding.slot}`).toBeDefined();
          expect(target.packageName).toBe(dependency.packageName);
          symbol = dependency.symbols.find((record: any) => record.id === target.symbolId);
          expect(target.moduleName).toBe(symbol?.moduleName);
        }
        expect(symbol, `${item.id}: ${target.symbolId}`).toBeDefined();
        expect(target.canonicalName).toBe(symbol.canonicalName);
        expect(target.category).toBe(symbol.category);
        if (target.category === "constructor") expect(target.ownerTypeId).toBe(symbol.ownerTypeId);
        expect(target.links).toEqual(symbol.links);
        expect(target.provenance).toEqual(symbol.provenance);
      }
    }
  });

  test("equivalent authoring layouts have identical authored module and model observations", () => {
    const corpus = json("cases.json");
    const groupIds = new Set<string>();
    for (const group of corpus.equivalenceGroups) {
      expect(groupIds.has(group.id), group.id).toBe(false);
      groupIds.add(group.id);
      expect(group.cases.length, group.id).toBeGreaterThanOrEqual(2);
      const observations = group.cases.map((id: string) => {
        const item = corpus.cases.find((record: any) => record.id === id);
        expect(item?.expected.observation, `${group.id}: ${id}`).toBeDefined();
        return json(item.expected.observation);
      });
      for (const observation of observations.slice(1)) {
        expect(observation.modules, group.id).toEqual(observations[0].modules);
        expect(observation.model, group.id).toEqual(observations[0].model);
      }
    }
  });

  test("the pinned template head and every section navigation link survive", () => {
    const html = bytes("contract.html").toString("utf8");
    expect(digest(html.match(/<head>[\s\S]*?<\/head>/)?.[0] ?? ""))
      .toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    const ids = [...rendered.matchAll(/<section id="([^"]+)"/g)].map(match => match[1]);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of ids) expect(toc).toContain(`href="#${id}"`);
  });
});
