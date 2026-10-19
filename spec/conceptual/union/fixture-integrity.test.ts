import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";

// Integrity of an independently authored reference corpus, not a Union interpreter.
const bytes = (path: string) => readFileSync(new URL(path, import.meta.url));
const json = (path: string) => JSON.parse(bytes(path).toString("utf8"));
const sha256 = (data: string | Uint8Array) => createHash("sha256").update(data).digest("hex");

describe("untagged union reference corpus integrity", () => {
  test("the contract, corpus, environment and byte inventory are published together", () => {
    for (const path of ["contract.html", "cases.json", "environment.json", "assets.json"])
      expect(existsSync(new URL(path, import.meta.url)), path).toBe(true);
  });

  test("reviewed bytes match the inventory and all JSON parses", () => {
    for (const asset of json("assets.json").assets) {
      const data = bytes(asset.path);
      expect(data.byteLength, asset.path).toBe(asset.bytes);
      expect(sha256(data), asset.path).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(data.toString("utf8"));
    }
  });

  test("cases have unique identities, resolved fixture references and explicit outcomes", () => {
    const corpus = json("cases.json");
    const environment = json(corpus.environment);
    const ids = new Set<string>();
    expect(corpus.status).toBe("reference-only");
    expect(corpus.profile).toBe("morphir-untagged-union/0.1.0-draft.1");
    const visit = (value: unknown): void => {
      if (value === null || typeof value !== "object") return;
      for (const [key, child] of Object.entries(value)) {
        if (key === "typeRef") expect(Object.hasOwn(environment.types, String(child)), String(child)).toBe(true);
        if (key === "codecProfile") expect(Object.hasOwn(environment.codecProfiles, String(child)), String(child)).toBe(true);
        visit(child);
      }
    };
    for (const item of corpus.cases) {
      expect(ids.has(item.id), item.id).toBe(false);
      ids.add(item.id);
      expect(item.description.length).toBeGreaterThan(0);
      expect(item.expected.outcome.length).toBeGreaterThan(0);
      visit(item.input);
    }
    for (const [requirement, cases] of Object.entries(corpus.coverage)) {
      expect(Array.isArray(cases), requirement).toBe(true);
      for (const id of cases as string[]) expect(ids.has(id), `${requirement}: ${id}`).toBe(true);
    }
  });

  test("the published HTML retains the template head and links every section", () => {
    const html = bytes("contract.html").toString("utf8");
    const head = html.match(/<head>[\s\S]*?<\/head>/)?.[0] ?? "";
    expect(sha256(head)).toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    const ids = [...rendered.matchAll(/<section id="([^"]+)"/g)].map((match) => match[1]);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of ids) expect(toc).toContain(`href="#${id}"`);
  });
});
