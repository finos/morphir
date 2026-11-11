// Fixed-data integrity only. Authentication and binding behavior belong to the one .NET runner.
import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const folder = "docs/spec/toolchain/preview/corpus/signed";
const digest = (bytes: string | Buffer) => createHash("sha256").update(bytes).digest("hex");
const load = (name: string) => JSON.parse(readFileSync(`${folder}/${name}`, "utf8"));
const canonical = (value: any): string => Array.isArray(value)
	? `[${value.map(canonical).join(",")}]`
	: value !== null && typeof value === "object"
		? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`
		: JSON.stringify(value);
const expected = [
	["complete-bindings-accepted", "accept", null, null],
	["host-descriptor-identity-refused", "refuse", "release_descriptor_mismatch", "hosts[0].source"],
	["host-platform-substitution-refused", "refuse", "artifact_platform_mismatch", "hosts[0].platforms.win-x64.target"],
	["provider-repository-substitution-refused", "refuse", "repository_mismatch", "providers[0].repositoryId"],
	["provider-descriptor-digest-refused", "refuse", "target_digest_mismatch", "providers[0].descriptorSha256"],
	["provider-protocol-disagreement-refused", "refuse", "release_descriptor_mismatch", "providers[0].protocolVersion"],
	["provider-model-disagreement-refused", "refuse", "release_descriptor_mismatch", "providers[0].modelTuple"],
	["provider-artifact-digest-refused", "refuse", "target_digest_mismatch", "providers[0].platforms.win-x64.artifactSha256"],
];

describe("preview signed binding fixture integrity", () => {
	test("eight independent binding expectations include a complete positive control", () => {
		const data = load("binding-cases.json");
		expect(data.cases.map((entry: any) => [entry.id, entry.expected.outcome,
			entry.expected.code ?? null, entry.expected.path ?? null])).toEqual(expected);
		for (const entry of data.cases) expect(entry.operation).toBe("check-recipe-bindings");
		expect(new Set(data.cases.map((entry: any) => entry.id)).size).toBe(8);
	});

	test("all cases bind exact repository bytes and retain the original fixture authority", () => {
		const data = load("binding-cases.json");
		const bytes = readFileSync(`${folder}/binding-repositories.json`);
		expect(data.repositoriesSha256).toBe(digest(bytes));
		const repositories = JSON.parse(bytes.toString("utf8"));
		const original = load("repository.json");
		expect(repositories.baselineSha256).toBe(digest(readFileSync(`${folder}/repository.json`)));
		expect(repositories.testOnly).toContain("TEST-ONLY");
		expect(repositories.trustedRoot).toEqual(original.trustedRoot);
		expect(repositories.repositoryId).toBe(original.repositoryId);
		expect(repositories.referenceTime).toBe(original.referenceTime);
		expect(Object.keys(repositories.variants).sort()).toEqual(data.cases.map((entry: any) => entry.repository).sort());
	});

	test("every target and envelope link matches its fixed bytes before behavioral checks", () => {
		const repositories = load("binding-repositories.json");
		for (const variant of Object.values(repositories.variants) as any[]) {
			const { targets, snapshot, timestamp } = variant.metadata;
			expect(Object.keys(targets.signed.targets).sort()).toEqual(Object.keys(variant.targetFiles).sort());
			for (const [target, text] of Object.entries(variant.targetFiles) as [string, string][]) {
				const record = targets.signed.targets[target];
				expect(record.length, target).toBe(Buffer.byteLength(text));
				expect(record.hashes.sha256, target).toBe(digest(text));
			}
			for (const [parent, child, name] of [[snapshot, targets, "targets.json"], [timestamp, snapshot, "snapshot.json"]] as const) {
				const link = parent.signed.meta[name];
				expect(link.version).toBe(child.signed.version);
				expect(link.length).toBe(Buffer.byteLength(canonical(child)));
				expect(link.hashes.sha256).toBe(digest(canonical(child)));
			}
		}
	});

	test("the protocol disagreement preserves host compatibility before comparing descriptor claims", () => {
		const variant = load("binding-repositories.json").variants["provider-protocol-disagreement-refused"];
		const recipe = JSON.parse(variant.targetFiles["toolchains/recipes/fsharp/1.0.0.json"]);
		const provider = recipe.providers[0];
		expect(provider.protocolVersion).toBe("0.2.0");
		for (const host of recipe.hosts) expect(host.protocolVersions).toContain(provider.protocolVersion);
		const descriptor = JSON.parse(variant.targetFiles[provider.descriptorTarget]);
		for (const artifact of descriptor.artifacts) {
			expect(artifact.claims.protocolVersions).toEqual(["0.2.0-draft.1"]);
		}
	});

	test("binding refusals remain schema-valid inputs rather than malformed-document controls", () => {
		const repositories = load("binding-repositories.json");
		const scratch = mkdtempSync(join(tmpdir(), "morphir-preview-binding-"));
		let checked = 0;
		try {
			for (const variant of Object.values(repositories.variants) as any[]) {
				for (const [target, text] of Object.entries(variant.targetFiles) as [string, string][]) {
					if (!target.endsWith(".json")) continue;
					const document = JSON.parse(text);
					const schema = document.$schema?.startsWith("https://morphir.finos.org/schemas/")
						? document.$schema.replace("https://morphir.finos.org/schemas/", "website/static/schemas/")
						: "website/static/schemas/tool-release-v1.schema.json";
					const file = join(scratch, "target.json");
					writeFileSync(file, text);
					const result = spawnSync("jsonschema", ["validate", schema, file,
						"-r", "website/static/schemas/toolchains/0.1.0-preview.1",
						"-r", "website/static/schemas/extensions/0.1.0-preview.1"],
						{ encoding: "utf8", windowsHide: true, timeout: 10_000 });
					expect(result.error, target).toBeUndefined();
					expect(result.status, `${target}: ${result.stdout} ${result.stderr}`).toBe(0);
					checked++;
				}
			}
			expect(checked).toBe(48);
		} finally {
			rmSync(scratch, { recursive: true, force: true });
		}
	}, 30_000);
});
