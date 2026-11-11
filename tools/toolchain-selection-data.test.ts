// Schema and corpus integrity only. Behavioral selection belongs to the .NET runner.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const schemas = "website/static/schemas/toolchains/0.1.0-preview.1";
const base = "https://morphir.finos.org/schemas/toolchains/0.1.0-preview.1/";
const corpus = "docs/spec/toolchain/preview/selection-cases.json";
const names = ["recipe", "request", "lock", "receipt", "result", "workflow-case", "selection"];
const load = (path: string): any => JSON.parse(readFileSync(path, "utf8"));

describe("toolchain selection contract data", () => {
  test("one schema family covers new documents without altering legacy schema identities", () => {
    expect(readdirSync(schemas).filter(n => n.endsWith(".schema.json")).sort())
      .toEqual(names.map(n => `${n}.schema.json`).sort());
    for (const name of names) {
      const schema = load(join(schemas, `${name}.schema.json`));
      expect(schema.$id).toBe(`${base}${name}.schema.json`);
      expect(schema.properties.schemaVersion).toBeUndefined();
      if (name === "request") {
        expect(schema.required).not.toContain("$schema"); // TOML carries a #:schema directive.
      } else {
        expect(schema.required).toContain("$schema");
        expect(schema.properties.$schema.const).toBe(schema.$id);
      }
    }
    for (const legacy of readdirSync("website/static/schemas").filter(n => /^(toolset-recipe|toolchain-|morphirup-result).*0\.1\.0-draft\.1\.schema\.json$/.test(n))) {
      const schema = load(join("website/static/schemas", legacy));
      expect(schema.$id).toBe(`https://morphir.finos.org/schemas/${legacy}`);
      expect(schema.properties.schemaVersion.const).toBe("0.1.0-draft.1");
    }
  });

  test("fixed cases enumerate the approved selection decisions", () => {
    const manifest = load(corpus);
    expect(manifest.contract).toBe(`${base}selection.schema.json`);
    const ids = manifest.cases.map((c: any) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const id of ["project-local-inventory", "overlay-precedes-project", "broken-pin-no-fallback",
      "isolated-omits-catalog-system", "relative-overlay-refused", "missing-platform-refused",
      "duplicate-id-refused", "unknown-schema-refused", "portable-wasm", "missing-local-object",
      "credential-refused", "absolute-path-refused"]) expect(ids).toContain(id);
    for (const c of manifest.cases) {
      expect(typeof c.operation, c.id).toBe("string");
      expect(["accept", "refuse"], c.id).toContain(c.expected.outcome);
      expect(c.input, c.id).toBeDefined();
    }
  });

  test("schemas validate structure and every schema-expressible corpus expectation", () => {
    const scratch = mkdtempSync(join(tmpdir(), "morphir-selection-schema-"));
    try {
      for (const name of names) {
        const result = spawnSync("jsonschema", ["metaschema", join(schemas, `${name}.schema.json`)], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
        expect(result.status, result.stderr).toBe(0);
      }
      const documents = load(corpus).cases.flatMap((c: any) => c.schemaDocuments ?? []);
      expect(documents.length).toBeGreaterThan(8);
      for (const [index, document] of documents.entries()) {
        const path = join(scratch, `${index}.json`);
        writeFileSync(path, JSON.stringify(document.document));
        const result = spawnSync("jsonschema", ["validate", join(schemas, "selection.schema.json"), path, "-r", schemas,
          "-r", "website/static/schemas/extensions/0.1.0-preview.1"], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
        expect(result.status === 0, `${index}: ${result.stdout} ${result.stderr}`).toBe(document.valid);
      }
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }, 30_000);

  test("configuration vectors distinguish installed identities from existing launch sources", () => {
    const cases = new Map<string, any>(load(corpus).cases.map((c: any) => [c.id, c]));
    for (const [id, outcome] of [
      ["configured-installed-id", "accept"],
      ["configured-id-path-conflict", "refuse"],
      ["configured-id-command-conflict", "refuse"],
      ["configured-id-url-conflict", "refuse"],
      ["configured-id-key-mismatch", "refuse"],
      ["configured-legacy-path", "accept"],
      ["configured-frontend-id", "accept"],
      ["configured-frontend-source-conflict", "refuse"],
    ] as const) {
      const entry = cases.get(id);
      expect(entry, id).toBeDefined();
      expect(entry.operation, id).toBe("read-provider-configuration");
      expect(entry.expected.outcome, id).toBe(outcome);
      expect(typeof entry.input.text, id).toBe("string");
    }
    expect(cases.get("configured-installed-id").expected.extensionId).toBe("acme.installed");
    expect(cases.get("configured-legacy-path").expected.path).toBe("./local.wasm");
    expect(cases.get("configured-frontend-id").expected.extensionId).toBe("acme.installed");
  });
});
