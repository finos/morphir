// Fixed-data integrity and schema structure only. The one .NET runner owns behavior.
import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const root = "docs/spec/toolchain/preview/corpus";
const base = "https://morphir.finos.org/schemas/toolchains/0.1.0-preview.1/";
const schemas = "website/static/schemas/toolchains/0.1.0-preview.1";
const names = ["recipe", "request", "lock", "receipt", "result", "workflow-case", "selection"];
interface Vector {
	id: string;
	contract: string;
	file: string;
	sha256: string;
	expected: { outcome: "accept" | "refuse"; reason?: string };
	schemaValid: boolean;
}
const manifest = (): { family: string; documents: Vector[] } =>
	JSON.parse(readFileSync(join(root, "cases.json"), "utf8"));

describe("current toolchain family fixed document corpus", () => {
	test("every family document has an independent positive and exact-schema refusal", () => {
		const data = manifest();
		expect(data.family).toBe(base);
		expect(new Set(data.documents.map(row => row.id)).size).toBe(data.documents.length);
		for (const name of names) {
			const vectors = data.documents.filter(row => row.contract === name);
			expect(vectors.some(row => row.expected.outcome === "accept"), name).toBe(true);
			expect(vectors.some(row => row.expected.reason === "unsupported-schema"), name).toBe(true);
		}
	});

	test("all inputs have fixed bytes and positive documents carry the current schema first", () => {
		for (const row of manifest().documents) {
			expect(names, row.id).toContain(row.contract);
			expect(row.file, row.id).not.toMatch(/(^\/|\\|(?:^|\/)\.\.(?:\/|$))/);
			const bytes = readFileSync(row.file);
			expect(createHash("sha256").update(bytes).digest("hex"), row.id).toBe(row.sha256);
			if (row.expected.outcome !== "accept") continue;
			const text = bytes.toString("utf8");
			if (row.contract === "request") {
				expect(text.split("\n")[0]).toBe(`#:schema ${base}request.schema.json`);
				expect((Bun.TOML.parse(text) as Record<string, unknown>).schemaVersion).toBeUndefined();
			} else {
				const document = JSON.parse(text);
				expect(Object.keys(document)[0], row.id).toBe("$schema");
				expect(document.$schema, row.id).toBe(`${base}${row.contract}.schema.json`);
				expect(document.schemaVersion, row.id).toBeUndefined();
			}
		}
	});

	test("schema expectations stay separate from reader expectations", () => {
		const scratch = mkdtempSync(join(tmpdir(), "morphir-current-family-"));
		try {
			for (const row of manifest().documents) {
				const text = readFileSync(row.file, "utf8");
				const value = row.contract === "request" ? Bun.TOML.parse(text) : JSON.parse(text);
				const file = join(scratch, "document.json");
				writeFileSync(file, JSON.stringify(value));
				const result = spawnSync("jsonschema", ["validate", join(schemas, `${row.contract}.schema.json`), file,
					"-r", schemas, "-r", "website/static/schemas/extensions/0.1.0-preview.1"],
					{ encoding: "utf8", windowsHide: true, timeout: 10_000 });
				expect(result.error, row.id).toBeUndefined();
				expect(result.status === 0, `${row.id}: ${result.stdout} ${result.stderr}`).toBe(row.schemaValid);
			}
		} finally {
			rmSync(scratch, { recursive: true, force: true });
		}
	}, 30_000);

	test("positive documents bind the actual request, recipe and lock bytes", () => {
		const rows = new Map(manifest().documents.map(row => [row.id, row]));
		const bytes = (id: string) => readFileSync(rows.get(id)!.file);
		const digest = (id: string) => createHash("sha256").update(bytes(id)).digest("hex");
		const lock = JSON.parse(bytes("lock-accepted").toString("utf8"));
		const receipt = JSON.parse(bytes("receipt-accepted").toString("utf8"));
		expect(lock.requestSha256).toBe(digest("request-accepted"));
		expect(lock.recipe.sha256).toBe(digest("recipe-accepted"));
		expect(receipt.lockSha256).toBe(digest("lock-accepted"));
		expect(receipt.recipe).toEqual(lock.recipe);
		expect(receipt.readiness).toBe("capability-checked");
		expect(receipt.checks).toEqual([{ check: "workflow", status: "skipped",
			workflow: "fsharp-compile-generate", reason: "Reader-only fixture: no workflow was run." }]);
	});

	test("the new workflow manifest references the original frozen resources in place", () => {
		const entry = manifest().documents.find(row => row.id === "workflow-case-accepted")!;
		expect(entry.file).toBe("spec/toolchain/workflows/fsharp-compile-generate/case.preview.json");
		const workflow = JSON.parse(readFileSync(entry.file, "utf8"));
		const historical = JSON.parse(readFileSync("spec/toolchain/workflows/fsharp-compile-generate/case.json", "utf8"));
		const { $schema: currentSchema, ...currentBody } = workflow;
		const { schemaVersion: historicalVersion, ...historicalBody } = historical;
		expect(currentSchema).toBe(`${base}workflow-case.schema.json`);
		expect(historicalVersion).toBe("0.1.0-draft.1");
		expect(currentBody).toEqual(historicalBody);
		const generated = readFileSync("spec/toolchain/workflows/fsharp-compile-generate/expected/generated/Pricing.fs");
		expect(generated.length).toBe(112);
		expect(createHash("sha256").update(generated).digest("hex"))
			.toBe("64e08313f3e57be2c18995a2e8b275db9d921341958da2c8cd960c601c066de0");
	});
});
