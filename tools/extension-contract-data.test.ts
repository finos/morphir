// Data integrity and JSON Schema checks only. Behavioral execution belongs to .NET.
import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../docs/spec/extensions/", import.meta.url));
const load = (name: string) => JSON.parse(readFileSync(join(root, name), "utf8"));
const digest = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");
const scenarios = (change: string) => [...readFileSync(`openspec/changes/${change}/specs/extensions/${change === "allow-dotted-extension-ids" ? "extension-identity" : "extension-packages"}/spec.md`, "utf8").matchAll(/^#### Scenario: (.+)$/gm)].map(m => m[1]!);
const schemaRoot = "website/static/schemas/extensions/0.1.0-preview.1";

describe("shared extension contract data", () => {
 test("nested lock examples bind the same identity in the lock, claims and filename", () => {
  const cases = load("identity-cases.json").cases;
  for (const id of ["nested-members-lock-claims", "nested-closed-lock-claims"]) {
   const c = cases.find((c: any) => c.id === id);
   for (const lock of [c.input.document, ...c.schemaDocuments.map((d: any) => d.document)]) {
    expect(lock.extensionId, id).toBe(lock.index.claims.extension.id);
    expect(lock.name, id).toBe(lock.index.claims.extension.name);
   }
   if (c.input.file) expect(c.input.file).toBe(`locks/extensions/${c.input.document.extensionId}.json`);
  }
 });
 test("published requirements match the approved OpenSpec deltas", () => {
  for (const [page, change, capability] of [["identity", "allow-dotted-extension-ids", "extension-identity"], ["packages", "add-extension-packages", "extension-packages"]]) {
   const body = (s: string) => s.slice(s.indexOf("### Requirement:"));
   expect(body(readFileSync(join(root, `${page}.md`), "utf8"))).toBe(body(readFileSync(`openspec/changes/${change}/specs/extensions/${capability}/spec.md`, "utf8")));
  }
 });
 test("accepted CRLF history has distinct versions and consistent embedded claims", () => {
  const c = load("identity-cases.json").cases.find((c: any) => c.id === "crlf-history");
  expect(c.input.text).toContain("\r\n\r\n");
  const records = c.input.text.split("\n").filter((s: string) => s.trim()).map((s: string) => JSON.parse(s));
  expect(new Set(records.map((r: any) => r.version)).size).toBe(records.length);
  expect(records).toEqual(c.expected.records);
  for (const r of records) for (const a of r.artifacts) expect(a.claims.extension.version).toBe(r.version);
 });

 test("journal input supplies writer bytes rather than prescribing a serializer", () => {
  const c = load("identity-cases.json").cases.find((c: any) => c.input.operation === "commit-state");
  const journal: any = Object.values(c.expected.files)[0];
  for (const [input, saved] of [["lockBytes", "nextLock"], ["catalogBytes", "nextCatalog"]]) {
   expect(typeof c.input[input!]).toBe("string");
   expect([...Buffer.from(c.input[input!], "utf8")]).toEqual(journal[saved!]);
   expect(JSON.parse(c.input[input!])).toEqual(c.input[input === "lockBytes" ? "lock" : "catalog"]);
  }
 });

 test("each schema context applies the enclosing document's member policy recursively", () => {
  const visit = (schema: any, open: boolean, at: string, seen = new Set<string>()) => {
   if (!schema || typeof schema !== "object") return;
   if (schema.$ref) {
    if (seen.has(schema.$ref)) return;
    const next = new Set(seen).add(schema.$ref);
    const [url, fragment] = schema.$ref.split("#");
    let target = JSON.parse(readFileSync(join(schemaRoot, url.split("/").pop()), "utf8"));
    for (const key of (fragment ?? "").split("/").filter(Boolean)) target = target[key];
    visit(target, open, at, next);
   }
   if (schema.type === "object") expect(schema.additionalProperties, at).toBe(open);
   for (const [key, value] of Object.entries(schema.properties ?? {})) visit(value, open, `${at}.${key}`, seen);
   if (schema.items) visit(schema.items, open, `${at}[]`, seen);
   for (const key of ["allOf", "anyOf", "oneOf"]) for (const value of schema[key] ?? []) visit(value, open, at, seen);
   for (const key of ["if", "then", "else"]) visit(schema[key], open, at, seen);
  };
  for (const name of readdirSync(schemaRoot).filter(n => n.endsWith(".schema.json"))) visit(JSON.parse(readFileSync(join(schemaRoot, name), "utf8")), !["lock.schema.json", "journal.schema.json", "repositories.schema.json"].includes(name), name);
  const withoutPolicy = (s: any): any => Array.isArray(s) ? s.map(withoutPolicy) : s && typeof s === "object" ? Object.fromEntries(Object.entries(s).filter(([k]) => k !== "additionalProperties").map(([k, v]) => [k, withoutPolicy(v)])) : s;
  const claims = JSON.parse(readFileSync(join(schemaRoot, "claims.schema.json"), "utf8"));
  const release = JSON.parse(readFileSync(join(schemaRoot, "release.schema.json"), "utf8"));
  expect(withoutPolicy(claims.$defs.closedEmbedded)).toEqual(withoutPolicy(claims.$defs.embedded));
  expect(withoutPolicy(release.$defs.closedPackage)).toEqual(withoutPolicy(release.$defs.package));
 });

 test("install reuse includes same-size corruption and a live lease refusal", () => {
  const m = load("package-cases.json");
  const c = m.cases.find((c: any) => c.id === "reuse-same-size-corruption");
  expect(c).toBeDefined();
  expect(c.input.existingTree[0].bytes.length).toBe(c.input.verifiedTree[0].bytes.length);
  expect(c.input.existingTree[0].bytes).not.toEqual(c.input.verifiedTree[0].bytes);
  expect(c.expected.reuseExisting).toBe(false);
  expect(c.expected.recordedTree).toEqual(c.input.verifiedTree);
  for (const f of c.input.verifiedTree) {
   const line: string | undefined = c.input.manifest.split("\n").find((s: string) => s.endsWith(` ${f.path}`));
   expect(line ?? "", String(f.path)).toContain(digest(Buffer.from(f.bytes)));
  }
  const leased = m.cases.find((c: any) => c.id === "repair-leased-corrupt-tree");
  expect(leased.expected.code).toBe("package.publish_busy");
  expect(leased.expected.mutations).toEqual([]);
  expect(m.hostTests.some((t: any) => t.id === "repair-lease")).toBe(true);
 });
 for (const [file, change] of [["identity-cases.json", "allow-dotted-extension-ids"], ["package-cases.json", "add-extension-packages"]]) {
  test(`${file} covers approved scenarios with concrete cases or explicit host tests`, () => {
   const manifest = load(file!);
   const ids = manifest.cases.map((c: any) => c.id);
   expect(new Set(ids).size).toBe(ids.length);
   for (const scenario of scenarios(change!)) {
    const dataCases = manifest.cases.filter((c: any) => c.scenarios.includes(scenario));
    const hostTests = manifest.hostTests.filter((c: any) => c.scenarios.includes(scenario));
    expect(dataCases.length + hostTests.length, scenario).toBeGreaterThan(0);
   }
   for (const c of manifest.cases) {
    expect(Object.keys(c.input).length, c.id).toBeGreaterThan(0);
    expect(["accept", "refuse", "old-state", "report", "move", "recover"]).toContain(c.expected.outcome);
    if (c.expected.outcome === "refuse" || c.expected.outcome === "old-state") expect(c.expected.rule ?? c.expected.code ?? c.expected.file, c.id).toBeDefined();
   }
  });
 }

 test("every package refusal code has fixed case data or an OS-specific test", () => {
  const spec = readFileSync("openspec/changes/add-extension-packages/specs/extensions/extension-packages/spec.md", "utf8");
  const codes = new Set([...spec.matchAll(/`package\.([a-z_]+)`/g)].filter(m => !["format", "root", "executables"].includes(m[1]!)).map(m => `package.${m[1]}`));
  const manifest = load("package-cases.json");
  const covered = new Set([...manifest.cases.map((c: any) => c.expected.code), ...manifest.hostTests.map((c: any) => c.code)]);
  for (const code of codes) expect(covered.has(code), code).toBe(true);
 });

 test("archive bytes and tree manifests match their frozen digests", () => {
  for (const c of load("package-cases.json").cases) {
   if (c.input.archive) {
    const bytes = readFileSync(join(root, c.input.archive));
    expect(digest(bytes), c.id).toBe(c.input.bytesSha256);
    expect(bytes.length, c.id).toBe(c.input.archiveLength);
   }
   if (c.expected.manifest) expect(digest(Buffer.from(c.expected.manifest, "ascii")), c.id).toBe(c.expected.treeSha256);
  }
 });

 test("checked-in fixture filenames are portable even when their archive entries are unsafe", () => {
  for (const name of readdirSync(join(root, "fixtures"))) expect(name).not.toMatch(/^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i);
 });

 test("gzip fixture headers do not depend on the generator's operating system", () => {
  for (const name of readdirSync(join(root, "fixtures")).filter(n => n.endsWith(".tgz"))) expect(readFileSync(join(root, "fixtures", name))[9], name).toBe(255);
 });

 test("publication evidence covers every required repository, package and pinned descriptor", () => {
  const audit = load("publication-audit.json");
  expect(audit.outcome).toBe("PKGVER-A");
  expect(audit.schemasPublishedAtApproval).toBe(false);
  expect(audit.dottedTask1_7CompleteAtApproval).toBe(false);
  expect(new Set(audit.inventories.map((r: any) => r.repository))).toEqual(new Set(["finos/morphir", "finos/morphir-dotnet", "finos/morphir-rust", "finos/morphir-moonbit", "finos/morphir-extensions", "finos/morphir-python", "finos/morphir-elm", "finos/morphir-scala"]));
  expect(audit.nuget.inspection.length).toBe(audit.nuget.packages.length);
  for (const p of audit.nuget.inspection) expect(p.preview1Occurrences).toEqual([]);
  for (const a of audit.metadataAssets) {
   expect(Boolean(a.containsPreview1), a.url).toBe(false);
   expect(a.updated <= audit.approvalCutoff, a.url).toBe(true);
  }
  const pins = Bun.TOML.parse(readFileSync(".config/published-extension-bundles.toml", "utf8")) as Record<string, Record<string, {repository?: string; tag: string}>>;
  for (const pin of [...Object.values(pins.bundles!), ...Object.values(pins.executables!)]) expect(audit.metadataAssets.some((a: any) => a.repository === (pin.repository ?? "finos/morphir-rust") && a.tag === pin.tag && a.extensionId), pin.tag).toBe(true);
  expect(audit.dotnetDocumentation.checked.length).toBe(160);
 });

 test("published URLs map to static files and shared member tables match the schemas", () => {
  const config = readFileSync("website/docusaurus.config.js", "utf8");
  expect(config).toContain("url: 'https://morphir.finos.org'");
  expect(config).toContain("baseUrl: '/'");
  const page = readFileSync("docs/design/draft/extensions/distribution-and-acquisition.md", "utf8");
  for (const file of readdirSync(schemaRoot).filter(n => n.endsWith(".schema.json"))) {
   const schema = JSON.parse(readFileSync(join(schemaRoot, file), "utf8"));
   expect(schema.$id).toBe(`https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/${file}`);
   for (const name of Object.keys(schema.properties)) expect(page, `${file}: ${name}`).toContain(`| \`${name}\` |`);
  }
 });

 test("shared-file member tables quote path and object placeholders for MDX", () => {
  const page = readFileSync("docs/design/draft/extensions/distribution-and-acquisition.md", "utf8");
  const prose = page.replace(/```[\s\S]*?```/g, "").replace(/`[^`\n]*`/g, "");
  expect(prose.match(/<(?:treeSha256|entryPoint)>|[{}]/g)).toBeNull();
 });

 test("the published id schema expresses every grammar, length and device-name example", () => {
  const temp = mkdtempSync(join(tmpdir(), "morphir-extension-ids-"));
  try {
   const schema = join(temp, "id.schema.json");
   writeFileSync(schema, JSON.stringify({$schema: "https://json-schema.org/draft/2020-12/schema", $ref: "https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json#/$defs/id"}));
   for (const c of load("identity-cases.json").cases.filter((c: any) => c.input.operation === "parse-id")) {
    const input = join(temp, "input.json"); writeFileSync(input, JSON.stringify(c.input.value));
    const result = spawnSync("jsonschema", ["validate", schema, input, "-r", schemaRoot], {encoding:"utf8", windowsHide:true});
    expect(result.status === 0, `${c.id}: ${result.stdout} ${result.stderr}`).toBe(c.expected.outcome === "accept");
   }
  } finally { rmSync(temp, {recursive:true, force:true}); }
 }, 30_000);

 test("regenerating package data changes no bytes", () => {
  const temp = mkdtempSync(join(tmpdir(), "morphir-extension-fixtures-"));
  try {
   const result = spawnSync("bun", ["tools/gen-extension-package-fixtures.ts", "--output", temp], {encoding:"utf8", windowsHide:true});
   expect(result.status, result.stderr).toBe(0);
   expect(readFileSync(join(temp, "package-cases.json"))).toEqual(readFileSync(join(root, "package-cases.json")));
   for (const name of readdirSync(join(temp, "fixtures"))) expect(readFileSync(join(temp, "fixtures", name)), name).toEqual(readFileSync(join(root, "fixtures", name)));
  } finally { rmSync(temp, {recursive:true, force:true}); }
 }, 30_000);

 test("all seven published schemas validate their examples and schema-expressible refusals", () => {
  const temp = mkdtempSync(join(tmpdir(), "morphir-extension-schemas-"));
  try {
   const schemas = readdirSync(schemaRoot).filter(n => n.endsWith(".schema.json"));
   expect(schemas.length).toBe(7);
   for (const name of schemas) {
    const schema = JSON.parse(readFileSync(join(schemaRoot, name), "utf8"));
    expect(schema.$id).toBe(`https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/${name}`);
    const result = spawnSync("jsonschema", ["metaschema", join(schemaRoot, name)], {encoding:"utf8", windowsHide:true});
    expect(result.status, result.stderr).toBe(0);
   }
   const documents = [...load("identity-cases.json").cases, ...load("package-cases.json").cases].flatMap((c: any) => c.schemaDocuments ?? []);
   expect(new Set(documents.filter((d: any) => d.valid).map((d: any) => d.schema)).size).toBe(7);
   for (const [i, d] of documents.entries()) {
    const path = join(temp, `${i}.json`); writeFileSync(path, JSON.stringify(d.document));
    const result = spawnSync("jsonschema", ["validate", join(schemaRoot, d.schema), path, "-r", schemaRoot], {encoding:"utf8", windowsHide:true});
    expect(result.status === 0, `${d.schema}: ${result.stdout} ${result.stderr}`).toBe(d.valid);
   }
  } finally { rmSync(temp, {recursive:true, force:true}); }
 }, 30_000);
});
