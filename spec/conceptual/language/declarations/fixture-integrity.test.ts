import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";

// Corpus integrity only. Parser/resolver observations are authored, never computed here.
const bytes = (path: string) => readFileSync(new URL(path, import.meta.url));
const json = (path: string): any => JSON.parse(bytes(path).toString("utf8"));
const digest = (value: string | Uint8Array) => createHash("sha256").update(value).digest("hex");

describe("declaration reference corpus", () => {
  test("source fixtures and case references use .mfs and match the inventory", () => {
    const sourcePaths = readdirSync(new URL("sources/", import.meta.url))
      .filter(name => name !== ".gitattributes")
      .map(name => `sources/${name}`)
      .sort();
    expect(sourcePaths.length).toBeGreaterThan(0);
    for (const path of sourcePaths) expect(path.endsWith(".mfs"), path).toBe(true);
    const assets = json("assets.json").assets
      .map((asset: any) => String(asset.path))
      .filter((path: string) => path.startsWith("sources/") && path !== "sources/.gitattributes")
      .sort();
    const referenced = [...new Set<string>(json("cases.json").cases
      .map((item: any) => item.input.source?.asset)
      .filter(Boolean))].sort();
    expect(assets).toEqual(sourcePaths);
    for (const path of referenced) {
      expect(path.endsWith(".mfs"), path).toBe(true);
      expect(sourcePaths, path).toContain(path);
    }
  });

  test("structural decoding has positive and negative independent expectations", () => {
    const structure = json("cases.json").cases.filter((item: any) => item.stage === "structure");
    expect(structure.some((item: any) => item.expected.outcome === "accepted")).toBe(true);
    expect(structure.some((item: any) => item.expected.outcome === "rejected")).toBe(true);
    for (const item of structure) expect(item.input.ast, item.id).toBeDefined();
  });

  test("the reviewed corpus has pinned assets and unique case identities", () => {
    const corpus = json("cases.json");
    const assets = json("assets.json").assets;
    const paths = new Set<string>(assets.map((asset: any) => asset.path));
    expect(corpus.profile).toBe("morphir-declarations/0.1.0-draft.1");
    expect(corpus.status).toBe("reference-only");
    expect(new Set(corpus.cases.map((item: any) => item.id)).size).toBe(corpus.cases.length);
    for (const asset of assets) {
      const data = bytes(asset.path);
      expect(data.length, asset.path).toBe(asset.bytes);
      expect(digest(data), asset.path).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(data.toString("utf8"));
    }
    for (const item of corpus.cases) {
      for (const asset of [item.input.source?.asset, item.input.ast, item.input.environment].filter(Boolean)) {
        expect(paths.has(String(asset)), item.id).toBe(true);
      }
      if (item.stage === "syntax") {
        expect(String(item.input.source.id), String(item.id)).toBe(`source:${item.id}`);
        expect(String(item.input.source.revision), String(item.id)).toBe("fixture-1");
      }
      if (item.expected.ast) expect(paths.has(item.expected.ast), item.id).toBe(true);
      expect(["syntax", "structure", "resolution", "capability"]).toContain(item.stage);
      expect(item.expected.outcome.length, item.id).toBeGreaterThan(0);
    }
    for (const ids of Object.values(corpus.coverage) as string[][]) {
      expect(ids.length).toBeGreaterThan(0);
      for (const id of ids) expect(corpus.cases.some((item: any) => item.id === id), id).toBe(true);
    }
  });

  test("complete authored trees have exact source pairs and usable byte spans", () => {
    for (const item of json("cases.json").cases) {
      if (item.stage !== "syntax" && item.stage !== "resolution" && item.expected.outcome !== "accepted") continue;
      const astPath = item.expected.ast ?? item.input.ast;
      if (!astPath) continue;
      const fragment = json(astPath);
      const sources = new Map<string, string>(fragment.sources.map((source: any) => [source.id, source.text]));
      if (item.input.source) {
        expect(String(fragment.sources[0].text), String(item.id)).toBe(bytes(item.input.source.asset).toString("utf8"));
        expect(String(fragment.sources[0].id)).toBe(item.input.source.id);
        expect(String(fragment.sources[0].revision)).toBe(item.input.source.revision);
      }
      const ids = new Set<string>();
      const visit = (value: unknown): void => {
        if (!value || typeof value !== "object") return;
        const record = value as Record<string, any>;
        if ("span" in record) {
          expect(ids.has(record.id), `${item.id}: ${record.id}`).toBe(false);
          ids.add(record.id);
          const span = record.span;
          const text = sources.get(span.sourceId);
          expect(text, item.id).toBeDefined();
          const data = Buffer.from(text!);
          expect(span.unit).toBe("utf8-byte");
          expect(Number.isInteger(span.start) && Number.isInteger(span.end)).toBe(true);
          expect(span.start).toBeGreaterThanOrEqual(0);
          expect(span.end).toBeGreaterThanOrEqual(span.start);
          expect(span.end).toBeLessThanOrEqual(data.length);
          for (const offset of [span.start, span.end]) {
            expect(offset === data.length || (data[offset]! & 0xc0) !== 0x80, `${item.id}: byte ${offset}`).toBe(true);
          }
        }
        for (const child of Object.values(record)) visit(child);
      };
      visit(fragment.declarations);
    }
  });

  test("diagnostic pointers and syntax error locations select supplied inputs", () => {
    for (const item of json("cases.json").cases) {
      for (const diagnostic of item.expected.diagnostics ?? []) {
        if (diagnostic.path) {
          let value: any = json(item.input.ast);
          for (const part of diagnostic.path.slice(1).split("/")) {
            const key = part.replaceAll("~1", "/").replaceAll("~0", "~");
            expect(Object.hasOwn(value, key), `${item.id}: ${diagnostic.path}`).toBe(true);
            value = value[key];
          }
        }
        if (diagnostic.span) {
          expect(item.input.source, item.id).toBeDefined();
          expect(diagnostic.span.sourceId).toBe(item.input.source.id);
          expect(diagnostic.span.start).toBeGreaterThanOrEqual(0);
          expect(diagnostic.span.end).toBeLessThanOrEqual(bytes(item.input.source.asset).length);
        }
      }
      if (item.stage === "syntax" && item.expected.outcome === "rejected") {
        expect(item.expected.ast).toBeUndefined();
        expect(item.input.ast).toBeUndefined();
      }
    }
  });

  test("reference shapes preserve the distinctions downstream tools must consume", () => {
    const declaration = (name: string) => json(`fixtures/${name}.json`).declarations[0];
    expect(declaration("flat-eight").value.elements).toHaveLength(8);
    expect(declaration("nested-pairs").value.elements.map((element: any) => element.kind)).toEqual(["tuple", "tuple"]);
    expect(declaration("nullary-constructor").kind).toBe("custom");
    expect(declaration("nullary-constructor").constructors[0].arguments).toEqual([]);
    expect(declaration("alias-to-existing-type").value.path).toEqual(["Domain", "Quantity"]);
    expect(declaration("constructor-two-arguments").constructors[0].arguments).toHaveLength(2);
    expect(declaration("constructor-applied-argument").constructors[0].arguments).toHaveLength(1);
    expect(declaration("function-tuple-input").inputs).toHaveLength(1);
    expect(declaration("function-two-inputs").inputs).toHaveLength(2);
    expect(declaration("function-valued-output").output.kind).toBe("function");
    expect(declaration("union-duplicates").value.members.map((member: any) => member.path)).toEqual([["Int"], ["Int"]]);
    expect(declaration("union-nested").value.members[1].kind).toBe("union");
    expect(declaration("application-union-arrow").value.input.kind).toBe("union");
    expect(declaration("right-associative-arrow").value.output.kind).toBe("function");
    expect(json("fixtures/utf8-crlf.json").sources[0].text).toBe("// π 😀\r\ntype alias Quantity = Int\r\n");
    expect(declaration("implicit-function-binder").typeParameters[0].origin).toBe("implicit");
  });

  test("the complete template head and section navigation survive publication", () => {
    const html = bytes("../contract.html").toString("utf8");
    expect(digest(html.match(/<head>[\s\S]*?<\/head>/)?.[0] ?? ""))
      .toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    const sectionIds = [...rendered.matchAll(/<section id="([^"]+)"/g)].map(match => match[1]);
    expect(new Set(sectionIds).size).toBe(sectionIds.length);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of sectionIds) expect(toc).toContain(`href="#${id}"`);
  });
});
