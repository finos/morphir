// Parent-owned documentation/data integrity only; host behavior is checked by the .NET runner.
import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

test("host report contract publishes one exact schema and fixed checker inputs", () => {
	const schemaUrl = "https://morphir.finos.org/schemas/wasm-host-reports/0.1.0-preview.1/report.schema.json";
	const schema = JSON.parse(readFileSync("website/static/schemas/wasm-host-reports/0.1.0-preview.1/report.schema.json", "utf8"));
	const cases = JSON.parse(readFileSync("spec/mep/mck/wasm-host-report.cases.json", "utf8"));
	const page = readFileSync("docs/spec/extensions/wasm-host-reports.md", "utf8");
	expect(schema.$id).toBe(schemaUrl);
	expect(schema.required).toContain("$schema");
	expect(schema.properties.$schema.const).toBe(schemaUrl);
	expect(schema.additionalProperties).toBe(false);
	expect(cases.reportSchema).toBe(schemaUrl);
	const ids = cases.cases.map((c: any) => c.id);
	for (const id of ["honest-failed-observations", "edited-verdict", "required-memory-not-enforced", "optional-budget-not-enforced", "wrong-offering-citation", "missing-published-guest", "duplicate-case", "missing-case", "unknown-schema"]) expect(ids).toContain(id);
	expect(new Set(ids).size).toBe(ids.length);
	expect(page).toContain(schemaUrl);
	expect(page).toContain("same shared runner");
	expect(page).toContain("not qualification evidence");
	expect(page).toContain("same host executable digest");
});

test("fixed host reports retain their schema-expressible results only", () => {
	const schemaPath = "website/static/schemas/wasm-host-reports/0.1.0-preview.1/report.schema.json";
	const cases = JSON.parse(readFileSync("spec/mep/mck/wasm-host-report.cases.json", "utf8"));
	const temp = mkdtempSync(join(tmpdir(), "morphir-host-report-schema-"));
	try {
		const meta = spawnSync("jsonschema", ["metaschema", schemaPath], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
		expect(meta.status, meta.stderr).toBe(0);
		for (const entry of cases.cases) {
			const input = join(temp, entry.id + ".json");
			writeFileSync(input, JSON.stringify(entry.report));
			const run = spawnSync("jsonschema", ["validate", schemaPath, input], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
			expect(run.error, entry.id).toBeUndefined();
			expect(run.signal, entry.id).toBeNull();
			expect(run.status === 0, `${entry.id}: ${run.stderr}`).toBe(entry.schemaValid);
		}
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}, 30_000);

test("synthetic host report inputs pin the unchanged corpus and local inert identities", () => {
	const data = JSON.parse(readFileSync("spec/mep/mck/wasm-host-report.cases.json", "utf8"));
	const corpus = JSON.parse(readFileSync("spec/mep/mck/wasm-host.cases.json", "utf8"));
	const hash = (path: string) => createHash("sha256").update(readFileSync(path)).digest("hex");
	const base = data.cases.find((c: any) => c.id === "honest-failed-observations").report;
	expect(base.cases.map((c: any) => c.caseId)).toEqual(corpus.cases.map((c: any) => c.caseId));
	for (const file of [base.runner, base.host, base.artifact, base.suite.corpus, base.suite.contract]) {
		expect(hash(join("spec/mep/mck", file.path ?? file.executable))).toBe(file.sha256);
	}
	expect(base.artifact.origin).toBe("synthetic");
	expect(base.verdict).toBe("not_qualified");
	for (const c of base.cases) expect(hash(join("spec/mep/mck", c.module.path))).toBe(c.module.sha256);
});

const contract = JSON.parse(readFileSync("spec/mep/wasm-execution-profiles.json", "utf8"));
const pagePath = "docs/spec/extensions/wasm-hosts.md";

test("published WASM profile tables retain every contract import, result and refusal", () => {
	const page = readFileSync(pagePath, "utf8");
	for (const [name, profile] of Object.entries<any>(contract.profiles)) {
		expect(page, name).toContain(`### ${name}`);
		for (const entry of profile.imports) {
			const signature = "(" + entry.params.join(", ") + ") -> " + (entry.results.length ? entry.results.join(", ") : "()");
			const quote = (value: string) => String.fromCharCode(96) + value + String.fromCharCode(96);
			expect(page).toContain("| " + quote(entry.module + "." + entry.name) + " | " + quote(signature) + " |");
			expect(page, `${name}: ${entry.module}.${entry.name}`).toContain(`\`${entry.module}.${entry.name}\``);
		}
		for (const result of profile.handleResults) {
			expect(page, `${name}: ${result.result}`).toContain(result.detail);
		}
	}
	for (const refusal of contract.refusals) expect(page).toContain(`\`${refusal.code}\``);
	for (const fault of contract.faults) expect(page).toContain(`\`${fault.kind}\``);
	for (const bound of contract.bounds.requiredForQualification) expect(page).toContain(`\`${bound}\``);
	for (const deviation of contract.knownDeviations) expect(page).toContain(deviation.tracking);
});

test("published WASM documentation distinguishes implemented observations from qualification", () => {
	const page = readFileSync(pagePath, "utf8");
	expect(page).toContain("No .NET offering/platform is declared qualified by this page.");
	expect(page).toContain("not_enforced");
	expect(page).toContain("notificationDelivery");
	expect(page).toContain("Unknown or absent values mean `none`");
	expect(page).toContain("guest-output");
	expect(page).toContain("268435456");
	expect(page).toContain("1048576");
	expect(page).toContain("16777216");
	expect(page).toContain("1024");
	expect(page).toContain("MORPHIR_EXTENSION_OVERLAY");
});

test("every sandbox policy leaf keeps its exact published value", () => {
	const page = readFileSync(pagePath, "utf8");
	const quote = (value: string) => String.fromCharCode(96) + value + String.fromCharCode(96);
	const visit = (value: Record<string, unknown>, prefix = "") => {
		for (const [name, child] of Object.entries(value)) {
			const key = prefix ? prefix + "." + name : name;
			if (child && typeof child === "object" && !Array.isArray(child)) {
				visit(child as Record<string, unknown>, key);
			} else {
				const text = typeof child === "string" ? child : JSON.stringify(child);
				expect(page, key).toContain("| " + quote(key) + " | " + quote(text) + " |");
			}
		}
	};
	visit(contract.policy);
});
