// Parent schema/data checks only. These objects are TEST-ONLY examples, not execution evidence.
import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const family = "https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.2/";
const folder = "website/static/schemas/local-toolchains/0.1.0-preview.2";
const original = JSON.parse(readFileSync("docs/spec/toolchain/local/candidate.example.json", "utf8"));
const frontend = "org.finos.morphir.fsharp-frontend";
const backend = "org.finos.morphir.fsharp-backend";
const digest = (n: number) => n.toString().repeat(64);
const candidate = { ...original, $schema: `${family}candidate.schema.json`, extensions: { selectionSha256: digest(1), frontendId: frontend, backendId: backend } };
const checks = [{ check: "integrity", status: "passed" }, { check: "capability", status: "passed" }];
const provider = (role: string, extensionId: string, operation: string) => ({
	role, extensionId, version: "1.2.3", mepVersion: "0.2.0-draft.1",
	modelTuple: { operation, profile: "morphir-ir", codec: "morphir-json", envelopeVersion: "0.1.0-draft.1", irVersion: "4.0.0" }, checks,
});
const generation = {
	$schema: `${family}generation.schema.json`, candidateSha256: digest(2), selectionSha256: digest(1), catalogSha256: digest(3),
	locks: [{ extensionId: backend, sha256: digest(4) }, { extensionId: frontend, sha256: digest(5) }], metadata: [],
	workflow: {
		case: "fsharp-compile-generate", caseSha256: digest(6), sourceSha256: digest(7),
		ir: { sha256: digest(8), semanticMatch: true }, generatedFiles: [{ path: "Pricing.fs", bytes: 112, sha256: "64e08313f3e57be2c18995a2e8b275db9d921341958da2c8cd960c601c066de0" }],
		providers: [provider("frontend", frontend, "morphir.frontend.compileModel"), provider("backend", backend, "morphir.backend.generateModel")],
		checks: [{ check: "workflow", workflow: "fsharp-compile-generate", status: "passed" }],
	},
};

function validates(name: string, value: unknown): boolean {
	const schema = join(folder, `${name}.schema.json`);
	if (!existsSync(schema)) return false;
	const temp = mkdtempSync(join(tmpdir(), "morphir-local-composed-schema-"));
	try {
		const path = join(temp, "input.json");
		writeFileSync(path, JSON.stringify(value));
		const result = spawnSync("jsonschema", ["validate", schema, path, "--resolve", "website/static/schemas/toolchains/0.1.0-preview.1", "--resolve", "website/static/schemas/extensions/0.1.0-preview.1"], { encoding: "utf8", windowsHide: true, timeout: 5_000 });
		expect(result.error).toBeUndefined();
		expect(result.signal).toBeNull();
		return result.status === 0;
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

test("composed family publishes five exact closed schemas and preserves host declaration fields", () => {
	for (const name of ["candidate", "generation", "receipt", "selection", "result"]) {
		const path = join(folder, `${name}.schema.json`);
		expect(existsSync(path), path).toBe(true);
		const schema = JSON.parse(readFileSync(path, "utf8"));
		expect(schema.$id).toBe(`${family}${name}.schema.json`);
		expect(schema.properties.$schema.const).toBe(schema.$id);
		expect(schema.required).toContain("$schema");
		expect(schema.additionalProperties).toBe(false);
	}
	expect(validates("candidate", candidate)).toBe(true);
	expect(validates("candidate", original)).toBe(false);
});

test("generation binds launch records and actual workflow observations with no recipe authority", () => {
	expect(validates("generation", generation)).toBe(true);
	for (const field of ["catalogSha256", "locks", "metadata", "workflow"]) {
		const copy: Record<string, unknown> = structuredClone(generation);
		delete copy[field];
		expect(validates("generation", copy), field).toBe(false);
	}
	expect(validates("generation", { ...generation, repositoryId: digest(9) })).toBe(false);
	expect(validates("generation", { ...generation, $schema: `${family}generation.schema.json?other` })).toBe(false);
});

test("a qualified generation refuses missing tuples, duplicate roles and unsuccessful checks", () => {
	const first = generation.workflow.providers[0]!;
	const second = generation.workflow.providers[1]!;
	const cases = [
		{ ...generation.workflow, providers: [{ ...first, modelTuple: undefined }, second] },
		{ ...generation.workflow, providers: [first, { ...second, role: "frontend" }] },
		{ ...generation.workflow, providers: [{ ...first, modelTuple: { ...first.modelTuple, operation: "morphir.backend.generateModel" } }, second] },
		{ ...generation.workflow, checks: [{ check: "workflow", workflow: "fsharp-compile-generate", status: "skipped" }] },
		{ ...generation.workflow, ir: { ...generation.workflow.ir, semanticMatch: false } },
	];
	for (const workflow of cases) expect(validates("generation", { ...generation, workflow })).toBe(false);
});

test("a dry-run result cannot invent the observation-derived generation or a receipt", () => {
	const planned = { $schema: `${family}result.schema.json`, command: "setup", status: "planned", origin: "local-developer", candidateSha256: digest(2) };
	expect(validates("result", planned)).toBe(true);
	expect(validates("result", { ...planned, generationSha256: digest(3) })).toBe(false);
	expect(validates("result", { ...planned, receiptPath: `toolchains/generations/${digest(3)}/receipt.json` })).toBe(false);
	expect(validates("result", { ...planned, status: "installed" })).toBe(false);
});

test("selection and successful results bind the installed generation separately from the candidate", () => {
	const pointer = { $schema: `${family}selection.schema.json`, origin: "local-developer", generationSha256: digest(3), receiptSha256: digest(4), receiptPath: `toolchains/generations/${digest(3)}/receipt.json` };
	expect(validates("selection", pointer)).toBe(true);
	expect(validates("selection", { ...pointer, candidateSha256: digest(2) })).toBe(false);
	const shown = { $schema: `${family}result.schema.json`, command: "show", status: "shown", origin: "local-developer", candidateSha256: digest(2), generationSha256: digest(3), receiptPath: pointer.receiptPath };
	expect(validates("result", shown)).toBe(true);
	const missing: Record<string, unknown> = { ...shown };
	delete missing.generationSha256;
	expect(validates("result", missing)).toBe(false);
});

test("the composed receipt requires both identities and the workflow evidence reference", () => {
	const receipt = {
		$schema: `${family}receipt.schema.json`, origin: "local-developer", implementation: "dotnet", deployment: "self-contained", platform: "win-x64",
		version: original.version, sourceCommit: original.sourceCommit, buildIdentity: original.buildIdentity,
		candidateSha256: digest(2), generationSha256: digest(3), archiveSha256: original.archive.sha256,
		installationPath: `store/tools/sha256/${original.archive.sha256}`, entryPoint: original.entryPoint,
		owner: "manager-owned", readiness: "workflow-verified",
	};
	expect(validates("receipt", receipt)).toBe(true);
	for (const name of ["candidateSha256", "generationSha256"]) {
		const copy: Record<string, unknown> = { ...receipt };
		delete copy[name];
		expect(validates("receipt", copy)).toBe(false);
	}
	expect(validates("receipt", { ...receipt, readiness: "launch-verified" })).toBe(false);
	expect(validates("receipt", { ...receipt, origin: "authenticated" })).toBe(false);
});

test("generation data refuses unsafe output paths and hidden launch overrides", () => {
	for (const path of ["../Pricing.fs", "out/../Pricing.fs", "C:/Pricing.fs", "/Pricing.fs"]) {
		const workflow = { ...generation.workflow, generatedFiles: [{ ...generation.workflow.generatedFiles[0]!, path }] };
		expect(validates("generation", { ...generation, workflow })).toBe(false);
	}
	const provider = { ...generation.workflow.providers[0]!, arguments: ["--override"] };
	expect(validates("generation", { ...generation, workflow: { ...generation.workflow, providers: [provider, generation.workflow.providers[1]!] } })).toBe(false);
});

test("negotiated protocol versions use the existing MEP 0.2-line schema", () => {
	for (const [mepVersion, expected] of [["0.2.0-draft.2", true], ["0.2.1", true], ["0.1.0", false], ["0.2.1-rc.1", false], ["0.2.0+build", false]] as const) {
		const workflow = { ...generation.workflow, providers: [{ ...generation.workflow.providers[0]!, mepVersion }, generation.workflow.providers[1]!] };
		expect(validates("generation", { ...generation, workflow }), mepVersion).toBe(expected);
	}
});

test("selection planning names an existing generation but cannot claim an installed result", () => {
	const planned = { $schema: `${family}result.schema.json`, command: "select", status: "planned", origin: "local-developer", generationSha256: digest(3) };
	expect(validates("result", planned)).toBe(true);
	const absent: Record<string, unknown> = { ...planned };
	delete absent.generationSha256;
	expect(validates("result", absent)).toBe(false);
	expect(validates("result", { ...planned, command: "setup", status: "selected" })).toBe(false);
	expect(validates("result", { ...planned, status: "refused" })).toBe(false);
});
