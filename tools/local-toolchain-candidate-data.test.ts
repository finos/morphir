// Parent data/schema integrity only. The actual .NET manager owns behavior.
import { expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const base = "https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.1/";
const schemas = "website/static/schemas/local-toolchains/0.1.0-preview.1";
const example = "docs/spec/toolchain/local/candidate.example.json";
const candidate = JSON.parse(readFileSync(example, "utf8"));
const candidateHash = createHash("sha256").update(readFileSync(example)).digest("hex");

function validates(name: string, value: unknown): boolean {
	const temp = mkdtempSync(join(tmpdir(), "morphir-local-candidate-schema-"));
	try {
		const path = join(temp, "input.json");
		writeFileSync(path, JSON.stringify(value));
		const result = spawnSync("jsonschema", ["validate", join(schemas, `${name}.schema.json`), path], {
			encoding: "utf8", windowsHide: true, timeout: 5_000,
		});
		expect(result.error).toBeUndefined();
		expect(result.signal).toBeNull();
		return result.status === 0;
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

test("local provenance documents share one exact family version with closed named objects", () => {
	for (const name of ["candidate", "receipt", "selection", "result"]) {
		const path = join(schemas, `${name}.schema.json`);
		const schema = JSON.parse(readFileSync(path, "utf8"));
		expect(schema.$id).toBe(`${base}${name}.schema.json`);
		expect(schema.properties.$schema.const).toBe(schema.$id);
		expect(schema.required).toContain("$schema");
		expect(schema.additionalProperties).toBe(false);
		const result = spawnSync("jsonschema", ["metaschema", path], { encoding: "utf8", windowsHide: true, timeout: 5_000 });
		expect(result.status, result.stderr).toBe(0);
	}
});

test("the concrete source-built candidate keeps its complete 320-file identity", () => {
	expect(Object.keys(candidate)[0]).toBe("$schema");
	expect(validates("candidate", candidate)).toBe(true);
	expect(candidate.origin).toBe("local-developer");
	expect(candidate.archive.sha256).toBe("bff0dbad0d70b15843237ab74f163c014e858ccc6e8aad8a7ec654176a7c1a6e");
	expect(candidate.archive.bytes).toBe(58_042_046);
	expect(candidate.files.length).toBe(320);
	expect(new Set(candidate.files.map((file: { path: string }) => file.path.toLowerCase())).size).toBe(320);
	expect(candidate.files.reduce((sum: number, file: { bytes: number }) => sum + file.bytes, 0)).toBe(136_932_607);
	for (const name of ["morphir.exe", "coreclr.dll", "hostfxr.dll", "FSharp.Compiler.Service.dll", "FSharp.Core.dll"]) {
		expect(candidate.files.some((file: { path: string }) => file.path === name), name).toBe(true);
	}
	expect(candidate.files.find((file: { path: string }) => file.path === candidate.entryPoint.path).sha256).toBe(candidate.entryPoint.sha256);
	expect(candidate.version).toBe("0.4.0-alpha.4+eb7d164bccbb24e069087a61c0dd1ffffff326e5");
	expect(candidate.buildIdentity).toContain("workingTreeClean=false");
});

test("local candidate structure refuses another authority and an absent full inventory", () => {
	for (const patch of [
		{ $schema: `${base}candidate.schema.json?other` },
		{ origin: "authenticated" },
		{ deployment: "native-aot" },
		{ platform: "linux-x64" },
		{ extra: true },
		{ files: [] },
	]) expect(validates("candidate", { ...candidate, ...patch })).toBe(false);
});

test("planned output does not pretend installation happened", () => {
	expect(validates("result", { $schema: `${base}result.schema.json`, command: "setup", status: "planned", origin: "local-developer", candidateSha256: candidateHash })).toBe(true);
});

test("selected output can omit the redundant fixed pointer path", () => {
	expect(validates("result", { $schema: `${base}result.schema.json`, command: "select", status: "selected", origin: "local-developer", candidateSha256: candidateHash, receiptPath: `toolchains/generations/${candidateHash}/receipt.json` })).toBe(true);
});

test("a refusal requires an actual diagnostic and successful state requires identity", () => {
	const value = { $schema: `${base}result.schema.json`, command: "setup", origin: "local-developer" };
	expect(validates("result", { ...value, status: "refused" })).toBe(false);
	expect(validates("result", { ...value, status: "installed" })).toBe(false);
	expect(validates("result", { ...value, status: "refused", diagnostic: { code: "digest-mismatch", message: "The supplied archive has a different digest." } })).toBe(true);
});

test("a setup result cannot claim another operation's selected state", () => {
	expect(validates("result", { $schema: `${base}result.schema.json`, command: "setup", status: "selected", origin: "local-developer", candidateSha256: candidateHash, receiptPath: `toolchains/generations/${candidateHash}/receipt.json`, selectionPath: "toolchains/default.json" })).toBe(false);
});
