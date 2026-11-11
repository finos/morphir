// Metadata integrity only. Trust, signature, recipe binding and resolution execute in .NET.
import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const path = "docs/spec/toolchain/preview/corpus/signed/repository.json";
const load = () => JSON.parse(readFileSync(path, "utf8"));
const hash = (bytes: string) => createHash("sha256").update(bytes).digest("hex");
const schema = "https://morphir.finos.org/schemas/toolchains/0.1.0-preview.1/recipe.schema.json";
const platforms = ["win-x64", "win-arm64", "osx-x64", "osx-arm64", "linux-x64", "linux-arm64"];

describe("preview signed recipe fixture integrity", () => {
	test("JSON target payloads conform to their published document schemas", () => {
		const repository = load();
		const scratch = mkdtempSync(join(tmpdir(), "morphir-preview-signed-"));
		let checked = 0;
		try {
			for (const [target, bytes] of Object.entries(repository.targetFiles) as [string, string][]) {
				if (!target.endsWith(".json")) continue;
				const document = JSON.parse(bytes);
				const schemaPath = document.$schema?.startsWith("https://morphir.finos.org/schemas/")
					? document.$schema.replace("https://morphir.finos.org/schemas/", "website/static/schemas/")
					: "website/static/schemas/tool-release-v1.schema.json";
				const file = join(scratch, "target.json");
				writeFileSync(file, bytes);
				const result = spawnSync("jsonschema", ["validate", schemaPath, file,
					"-r", "website/static/schemas/toolchains/0.1.0-preview.1",
					"-r", "website/static/schemas/extensions/0.1.0-preview.1"],
					{ encoding: "utf8", windowsHide: true, timeout: 10_000 });
				expect(result.error, target).toBeUndefined();
				expect(result.status, `${target}: ${result.stdout} ${result.stderr}`).toBe(0);
				checked++;
			}
			expect(checked).toBe(6);
		} finally {
			rmSync(scratch, { recursive: true, force: true });
		}
	}, 30_000);

	test("the new repository has separate explicit TEST-ONLY keys and exact root bytes", () => {
		const repository = load();
		expect(repository.testOnly).toContain("TEST-ONLY");
		expect(repository.testOnlyKeys.length).toBe(5);
		for (const key of repository.testOnlyKeys) expect(key.label).toContain("TEST-ONLY");
		expect(JSON.parse(repository.initialRootSignedBytes)).toEqual(repository.trustedRoot.signed);
		expect(hash(repository.initialRootSignedBytes)).toBe(repository.repositoryId);
		const old = JSON.parse(readFileSync("docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/repository.json", "utf8"));
		expect(repository.repositoryId).not.toBe(old.repositoryId);
		for (const key of repository.testOnlyKeys) expect(old.testOnlyKeys.map((k: any) => k.keyId)).not.toContain(key.keyId);
	});

	test("all authenticated target records bind fixed inert bytes", () => {
		const repository = load();
		const targets = repository.metadata.targets.signed.targets;
		expect(Object.keys(targets).sort()).toEqual(Object.keys(repository.targetFiles).sort());
		for (const [target, record] of Object.entries(targets) as [string, any][]) {
			const bytes = repository.targetFiles[target];
			expect(Buffer.byteLength(bytes), target).toBe(record.length);
			expect(hash(bytes), target).toBe(record.hashes.sha256);
		}
		const target = "toolchains/recipes/fsharp/1.0.0.json";
		expect(targets[target].custom.morphir.$schema).toBe(schema);
		expect(targets[target].custom.morphir.schemaVersion).toBeUndefined();
		expect(JSON.parse(repository.targetFiles[target]).$schema).toBe(schema);
		expect(repository.recipeRevocation.targets.signed.targets[target].custom.morphir.status).toBe("revoked");
		expect(repository.recipeRevocation.targets.signed.targets[target].hashes).toEqual(targets[target].hashes);
	});

	test("four offering closures and both process providers cover exactly six native pairs", () => {
		const repository = load();
		const recipe = JSON.parse(repository.targetFiles["toolchains/recipes/fsharp/1.0.0.json"]);
		expect(recipe.hosts.map((host: any) => host.deployment)).toEqual(["native-aot", "self-contained", "framework-dependent", "dotnet-tool"]);
		for (const host of recipe.hosts) expect(Object.keys(host.platforms).sort()).toEqual([...platforms].sort());
		const tool = recipe.hosts.find((host: any) => host.deployment === "dotnet-tool");
		expect(tool.prerequisites).toContainEqual({ kind: "sdk", name: "dotnet", phase: "install", versions: [">=10.0.0", "<11.0.0"] });
		expect(tool.prerequisites).toContainEqual({ kind: "runtime", name: "dotnet", versions: [">=10.0.0", "<11.0.0"] });
		expect(recipe.providers.map((provider: any) => provider.operation)).toEqual(["compile", "generate"]);
		for (const provider of recipe.providers) {
			expect(provider.repositoryId).toBe(repository.repositoryId);
			expect(Object.keys(provider.platforms).sort()).toEqual([...platforms].sort());
			const descriptor = JSON.parse(repository.targetFiles[provider.descriptorTarget]);
			expect(descriptor.$schema).toBe("https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/release.schema.json");
			expect(descriptor.extensionId).toBe(provider.extensionId);
		}
	});

	test("fixed trust controls include real success and separate length, digest, signature, expiry and revocation refusals", () => {
		const cases = JSON.parse(readFileSync("docs/spec/toolchain/preview/corpus/signed/cases.json", "utf8"));
		expect(cases.recipeSchema).toBe(schema);
		const ids = cases.cases.map((entry: any) => entry.id);
		expect(new Set(ids).size).toBe(ids.length);
		for (const id of ["authenticated-preview-recipe", "recipe-length-refused", "recipe-digest-refused",
			"metadata-signature-refused", "timestamp-expiry-refused", "learned-recipe-revocation-refused"]) {
			expect(ids).toContain(id);
		}
		const repository = load();
		const original = repository.targetFiles["toolchains/recipes/fsharp/1.0.0.json"];
		const digestCase = cases.cases.find((entry: any) => entry.id === "recipe-digest-refused");
		const lengthCase = cases.cases.find((entry: any) => entry.id === "recipe-length-refused");
		expect(Buffer.byteLength(digestCase.targetBytes)).toBe(Buffer.byteLength(original));
		expect(hash(digestCase.targetBytes)).not.toBe(hash(original));
		expect(Buffer.byteLength(lengthCase.targetBytes)).toBe(Buffer.byteLength(original) - 1);
	});
});
