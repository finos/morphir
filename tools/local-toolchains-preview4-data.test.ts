// Parent schema and fixed-example checks for local-toolchains 0.1.0-preview.4.
// The example sets are TEST-ONLY data with synthetic digests, not execution
// evidence. The .NET manager owns behavior; the cross-document rules below are
// the stated rules of docs/spec/toolchain/local-platforms-and-release-bundle.md,
// checked here against fixed data only. That page now documents preview.5, so
// local-toolchains-preview5-data.test.ts checks the page against its examples.
import { expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const family = "https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.4/";
const folder = "website/static/schemas/local-toolchains/0.1.0-preview.4";
const examples = "docs/spec/toolchain/local/0.1.0-preview.4";
const repository = "https://github.com/finos/morphir-dotnet";
const names = ["bundle", "candidate", "generation", "receipt", "result", "selection"];
const resolve = ["--resolve", "website/static/schemas/toolchains/0.1.0-preview.1", "--resolve", "website/static/schemas/extensions/0.1.0-preview.1"];
const sha = (bytes: string | Buffer) => createHash("sha256").update(bytes).digest("hex");

/** Each document of a set and the schema it must satisfy. */
const documents: Record<string, string> = {
	"candidate.json": join(folder, "candidate.schema.json"),
	"receipt.json": join(folder, "receipt.schema.json"),
	"default.json": join(folder, "selection.schema.json"),
	"result.json": join(folder, "result.schema.json"),
	"generation.json": join(folder, "generation.schema.json"),
	"acquisition/bundle.json": join(folder, "bundle.schema.json"),
	"extensions/selection.json": "website/static/schemas/toolchains/0.1.0-preview.1/selection.schema.json",
};

function validatesFile(schema: string, path: string): boolean {
	const result = spawnSync("jsonschema", ["validate", schema, path, ...resolve], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
	expect(result.error).toBeUndefined();
	expect(result.signal).toBeNull();
	return result.status === 0;
}

function validates(name: string, value: unknown): boolean {
	const temp = mkdtempSync(join(tmpdir(), "morphir-local-preview4-schema-"));
	try {
		const path = join(temp, "input.json");
		writeFileSync(path, JSON.stringify(value));
		return validatesFile(join(folder, `${name}.schema.json`), path);
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

/** The archive file extension each platform's release assets use. */
const archiveExtension: Record<string, string> = { "win-x64": ".zip", "win-arm64": ".zip", "osx-arm64": ".tar.gz" };

const ruleNames = ["schema-first", "origin-agreement", "platform-agreement", "acquisition-by-origin", "asset-platform", "provider-platform", "bindings", "release-bindings"];
const sets = (kind: "valid" | "invalid") => readdirSync(join(examples, kind)).sort().map((name) => join(examples, kind, name));

function schemaFailures(set: string): string[] {
	return Object.entries(documents)
		.filter(([path]) => existsSync(join(set, path)))
		.filter(([path, schema]) => !validatesFile(schema, join(set, path)))
		.map(([path]) => path)
		.sort();
}

/** The stated cross-document rules. Returns the names of the rules a set breaks. */
function ruleFailures(set: string): string[] {
	const raw = (path: string) => readFileSync(join(set, path));
	const present = (path: string) => existsSync(join(set, path));
	const read = (path: string) => JSON.parse(raw(path).toString("utf8"));
	const candidate = read("candidate.json");
	const receipt = read("receipt.json");
	const selection = read("default.json");
	const result = read("result.json");
	const generation = read("generation.json");
	const pins = read("extensions/selection.json");
	const bundle = present("acquisition/bundle.json") ? read("acquisition/bundle.json") : undefined;
	const failures = new Set<string>();
	const rule = (name: string, holds: boolean) => {
		if (!ruleNames.includes(name)) throw new Error(`Unlisted rule ${name}`);
		if (!holds) failures.add(name);
	};

	rule("schema-first", Object.keys(documents).filter(present).every((path) => Object.keys(read(path))[0] === "$schema"));

	rule("origin-agreement", [receipt, selection, result].every((document) => document.origin === candidate.origin));

	rule("platform-agreement", receipt.platform === candidate.platform && (!bundle || bundle.platform === candidate.platform));

	rule("acquisition-by-origin", (candidate.origin === "release-checksum") === ("acquisition" in generation)
		&& ("acquisition" in generation) === (present("acquisition/bundle.json") && present("acquisition/SHA256SUMS")));

	const roleIds: [string, string][] = [["frontend", candidate.extensions.frontendId], ["backend", candidate.extensions.backendId]];
	const asset = (role: string) => bundle?.assets.find((entry: { role: string }) => entry.role === role);
	rule("provider-platform", roleIds.every(([role, id]) => {
		const pin = pins.extensions.find((entry: { extensionId: string }) => entry.extensionId === id);
		const digest = pin?.platforms?.[candidate.platform];
		return typeof digest === "string" && (!bundle || asset(`${role}-archive`)?.sha256 === digest);
	}));

	const candidateSha256 = sha(raw("candidate.json"));
	const generationSha256 = sha(raw("generation.json"));
	const receiptPath = `toolchains/generations/${generationSha256}/receipt.json`;
	rule("bindings", [receipt.candidateSha256, generation.candidateSha256, result.candidateSha256].every((value) => value === candidateSha256)
		&& [candidate.extensions.selectionSha256, generation.selectionSha256].every((value) => value === sha(raw("extensions/selection.json")))
		&& [receipt.generationSha256, selection.generationSha256, result.generationSha256].every((value) => value === generationSha256)
		&& selection.receiptSha256 === sha(raw("receipt.json"))
		&& selection.receiptPath === receiptPath && result.receiptPath === receiptPath
		&& ["implementation", "deployment", "version", "sourceCommit", "buildIdentity"].every((name) => receipt[name] === candidate[name])
		&& JSON.stringify(receipt.entryPoint) === JSON.stringify(candidate.entryPoint)
		&& receipt.archiveSha256 === candidate.archive.sha256
		&& receipt.installationPath === `store/tools/sha256/${candidate.archive.sha256}`
		&& roleIds.every(([, id]) => generation.locks.some((lock: { extensionId: string }) => lock.extensionId === id)));

	if (bundle) {
		const platform = bundle.platform;
		const extension = archiveExtension[platform];
		rule("asset-platform", asset("host-candidate")?.name === `morphir-host-candidate-${platform}.json`
			&& asset("selection")?.name === `morphir-extensions-${platform}.json`
			&& bundle.assets.every((entry: { name: string }) => entry.name.includes(`-${platform}.`))
			&& ["host-archive", "frontend-archive", "backend-archive"].every((role) => extension !== undefined && asset(role)?.name.endsWith(extension)));

		const sums = new Map<string, string>();
		let sumsWellFormed = true;
		for (const line of raw("acquisition/SHA256SUMS").toString("utf8").split("\n").filter(Boolean)) {
			const match = /^([0-9a-f]{64})  ([^/]+)$/.exec(line);
			if (!match || sums.has(match[2]!)) sumsWellFormed = false;
			else sums.set(match[2]!, match[1]!);
		}
		const acquisition = generation.acquisition ?? {};
		const metadata = (id: string) => generation.metadata.find((entry: { extensionId: string }) => entry.extensionId === id)?.sha256;
		rule("release-bindings", bundle.sourceCommit === candidate.sourceCommit
			&& bundle.version === String(candidate.version).split("+")[0]
			&& acquisition.tag === `v${bundle.version}`
			&& acquisition.bundle?.sha256 === sha(raw("acquisition/bundle.json"))
			&& acquisition.checksums?.sha256 === sha(raw("acquisition/SHA256SUMS"))
			&& bundle.assets.every((entry: { name: string; url: string }) => entry.url === `${repository}/releases/download/v${bundle.version}/${entry.name}`)
			&& new Set(bundle.assets.map((entry: { name: string }) => entry.name.toUpperCase())).size === bundle.assets.length
			&& asset("host-candidate")?.sha256 === candidateSha256 && asset("host-candidate")?.bytes === raw("candidate.json").length
			&& asset("host-archive")?.sha256 === candidate.archive.sha256 && asset("host-archive")?.bytes === candidate.archive.bytes
			&& asset("selection")?.sha256 === candidate.extensions.selectionSha256
			&& roleIds.every(([role, id]) => asset(`${role}-release`)?.sha256 === metadata(id))
			&& sumsWellFormed
			&& sums.get(`morphir-toolchain-${platform}.json`) === sha(raw("acquisition/bundle.json"))
			&& bundle.assets.every((entry: { name: string; sha256: string }) => sums.get(entry.name) === entry.sha256));
	}
	return [...failures].sort();
}

test("published previews 1, 2 and 3 stay byte for byte unchanged", () => {
	const pinned: Record<string, string> = {
		"0.1.0-preview.1/candidate.schema.json": "d03f1ce670881c842349cd3379187873a459a973c38ed706fce10d2a9986effc",
		"0.1.0-preview.1/receipt.schema.json": "043f87fea706070ea283d2ea8031da621d05ea55ed2d35364ffdd4310d57f1bf",
		"0.1.0-preview.1/result.schema.json": "33be0cb0e33d82e7e52f86fd87988cc75a62b9b16312817ff3d378087eb07dc0",
		"0.1.0-preview.1/selection.schema.json": "8acb31ad92cc4ff6fc4c90bcb56f0ef1753beed96bd2f490acff19df328ba46a",
		"0.1.0-preview.2/candidate.schema.json": "9d0e1859d7568d23271e423ca8b1c879d21964035ed1064a695b95eff914f19b",
		"0.1.0-preview.2/generation.schema.json": "984eb82e4070c1620e4651b6d876f6119aabb9f6aec66a1d4f00d9f67da80a18",
		"0.1.0-preview.2/receipt.schema.json": "4e3ed0f5274ea532ef1a29116765b95ee36bab4274790539de7a1d575df7a608",
		"0.1.0-preview.2/result.schema.json": "da99c8a7272b5e60dd1bd8e2013d243efaf6953a7956b8199a778f6e4507b52c",
		"0.1.0-preview.2/selection.schema.json": "c6c8d666154dcd1ab2d374883e2007c6b687d6c9a5fabccc91cbba59b7e6525e",
		"0.1.0-preview.3/bundle.schema.json": "49bd969ade54f05f74951d5550ac53ee35fd373153ab6dac9d9dc869f1e83b19",
		"0.1.0-preview.3/candidate.schema.json": "a8062f0caa5c6fc3769db54240eed4df95199e3bcb2af5dada33b4cbdbeec491",
		"0.1.0-preview.3/generation.schema.json": "eeb155d883282e16ec85034de79da218bac72d1cbfc9f1aab771940bca84bc33",
		"0.1.0-preview.3/receipt.schema.json": "80c3370addba538a1e6f38cc962b3b8dd8c1e479d1a7e70b4f434d3e89021f72",
		"0.1.0-preview.3/result.schema.json": "4fc9bdf3efa11077f97ccd313d8f9ed0a83300219b9b35a66131964b2fe77d0e",
		"0.1.0-preview.3/selection.schema.json": "d611e0bbc59ea93a8173b698112f970d2ea43d2df2e566f9d028f2622ca1dd2d",
	};
	const base = "website/static/schemas/local-toolchains";
	const actual = ["0.1.0-preview.1", "0.1.0-preview.2", "0.1.0-preview.3"].flatMap((version) =>
		readdirSync(join(base, version)).map((file) => `${version}/${file}`)).sort();
	expect(actual).toEqual(Object.keys(pinned).sort());
	for (const [path, digest] of Object.entries(pinned)) expect(sha(readFileSync(join(base, path))), path).toBe(digest);
});

test("preview.4 carries every preview.3 example set forward under the same name", () => {
	const earlier = "docs/spec/toolchain/local/0.1.0-preview.3";
	for (const kind of ["valid", "invalid"]) {
		const carried = readdirSync(join(earlier, kind));
		expect(readdirSync(join(examples, kind)), kind).toEqual(expect.arrayContaining(carried));
	}
});

test("preview.4 publishes six closed schemas carrying their own URL", () => {
	expect(readdirSync(folder).sort()).toEqual(names.map((name) => `${name}.schema.json`));
	for (const name of names) {
		const path = join(folder, `${name}.schema.json`);
		const schema = JSON.parse(readFileSync(path, "utf8"));
		expect(schema.$schema).toBe("https://json-schema.org/draft/2020-12/schema");
		expect(schema.$id).toBe(`${family}${name}.schema.json`);
		expect(schema.properties.$schema.const).toBe(schema.$id);
		expect(schema.required[0]).toBe("$schema");
		expect(schema.additionalProperties).toBe(false);
		const result = spawnSync("jsonschema", ["metaschema", path], { encoding: "utf8", windowsHide: true, timeout: 10_000 });
		expect(result.status, result.stderr).toBe(0);
	}
});

test("platform and origin members exist only where the family places them", () => {
	const schema = (name: string) => JSON.parse(readFileSync(join(folder, `${name}.schema.json`), "utf8"));
	for (const name of ["candidate", "receipt", "bundle"]) {
		expect(schema(name).properties.platform, name).toEqual({ enum: ["win-x64", "win-arm64", "osx-arm64"] });
		expect(schema(name).required, name).toContain("platform");
	}
	for (const name of ["selection", "result", "generation"]) expect(schema(name).properties.platform, name).toBeUndefined();
	for (const name of ["candidate", "receipt", "selection", "result"]) {
		expect(schema(name).properties.origin, name).toEqual({ enum: ["local-developer", "release-checksum"] });
	}
	for (const name of ["generation", "bundle"]) expect(schema(name).properties.origin, name).toBeUndefined();
	expect(schema("candidate").properties.sourceRepository).toEqual({ const: repository });
	expect(schema("generation").properties.acquisition.properties.repository).toEqual({ const: repository });
	expect(schema("generation").required).not.toContain("acquisition");
});

test("valid example sets satisfy every schema and every stated rule", () => {
	const valid = sets("valid");
	const covered = valid.map((set) => {
		const candidate = JSON.parse(readFileSync(join(set, "candidate.json"), "utf8"));
		return `${candidate.platform} ${candidate.origin}`;
	});
	expect(covered.sort()).toEqual([
		"osx-arm64 local-developer", "osx-arm64 release-checksum",
		"win-arm64 local-developer", "win-arm64 release-checksum",
		"win-x64 local-developer", "win-x64 release-checksum",
	]);
	for (const set of valid) {
		expect(schemaFailures(set), set).toEqual([]);
		expect(ruleFailures(set), set).toEqual([]);
	}
}, 120_000);

test("each invalid example set fails exactly the check it names", () => {
	const invalid = sets("invalid");
	expect(invalid.length).toBeGreaterThanOrEqual(9);
	for (const set of invalid) {
		const expected = JSON.parse(readFileSync(join(set, "expected.json"), "utf8"));
		expect(schemaFailures(set), set).toEqual(expected.schemaFailures ?? []);
		if (expected.ruleFailures) expect(ruleFailures(set), set).toEqual(expected.ruleFailures);
	}
}, 120_000);

test("a bundle names each of its nine roles exactly once and only official release URLs", () => {
	const bundle = JSON.parse(readFileSync(join(examples, "valid/win-arm64-release-checksum/acquisition/bundle.json"), "utf8"));
	expect(validates("bundle", bundle)).toBe(true);
	const assets = bundle.assets as Record<string, unknown>[];
	const first = assets[0]!;
	for (const changed of [
		assets.slice(1),
		[...assets, { ...first, name: "extra.json" }],
		[{ ...first, role: "selection" }, ...assets.slice(1)],
		[{ ...first, role: "sample" }, ...assets.slice(1)],
		[{ ...first, url: String(first.url).replace("https:", "http:") }, ...assets.slice(1)],
		[{ ...first, url: String(first.url).replace("finos/morphir-dotnet", "other/project") }, ...assets.slice(1)],
		[{ ...first, bytes: 0 }, ...assets.slice(1)],
		[{ ...first, bytes: 1_073_741_825 }, ...assets.slice(1)],
		[{ ...first, name: "nested/name.json" }, ...assets.slice(1)],
	]) expect(validates("bundle", { ...bundle, assets: changed })).toBe(false);
	expect(validates("bundle", { ...bundle, platform: "linux-arm64" })).toBe(false);
	expect(validates("bundle", { ...bundle, version: "v0.4.0" })).toBe(false);
}, 60_000);

test("each platform pairs with exactly one archive format and one entry point name", () => {
	const read = (set: string, name: string) => JSON.parse(readFileSync(join(examples, set, `${name}.json`), "utf8"));
	const sets: Record<string, string> = {
		"win-x64": "valid/win-x64-local-developer",
		"win-arm64": "valid/win-arm64-local-developer",
		"osx-arm64": "valid/osx-arm64-local-developer",
	};
	const pairs: Record<string, [string, string]> = { "win-x64": ["zip", "morphir.exe"], "win-arm64": ["zip", "morphir.exe"], "osx-arm64": ["tar-gzip", "morphir"] };
	for (const [platform, set] of Object.entries(sets)) {
		const candidate = read(set, "candidate");
		const receipt = read(set, "receipt");
		const [format, entry] = pairs[platform]!;
		expect([candidate.platform, candidate.archive.format, candidate.entryPoint.path], set).toEqual([platform, format, entry]);
		expect(validates("candidate", candidate), set).toBe(true);
		expect(validates("candidate", { ...candidate, entryPoint: { ...candidate.entryPoint, path: `bin/${entry}` } }), set).toBe(true);
		for (const [otherFormat, otherEntry] of [["zip", "morphir"], ["tar-gzip", "morphir.exe"]]) {
			if (otherFormat !== format) expect(validates("candidate", { ...candidate, archive: { ...candidate.archive, format: otherFormat } }), `${set} ${otherFormat}`).toBe(false);
			if (otherEntry !== entry) {
				const moved = { ...candidate.entryPoint, path: otherEntry };
				expect(validates("candidate", { ...candidate, entryPoint: moved }), `${set} ${otherEntry}`).toBe(false);
				expect(validates("receipt", { ...receipt, entryPoint: moved }), `${set} receipt ${otherEntry}`).toBe(false);
			}
		}
		expect(validates("receipt", receipt), set).toBe(true);
	}
	for (const platform of ["osx-x64", "linux-x64"]) expect(validates("candidate", { ...read(sets["osx-arm64"]!, "candidate"), platform })).toBe(false);
}, 120_000);

test("a generation's acquisition proof binds the two fixed retained files", () => {
	const generation = JSON.parse(readFileSync(join(examples, "valid/win-arm64-release-checksum/generation.json"), "utf8"));
	expect(validates("generation", generation)).toBe(true);
	const { acquisition } = generation;
	for (const changed of [
		{ ...acquisition, repository: "https://github.com/other/project" },
		{ ...acquisition, tag: "0.4.0-alpha.5" },
		{ ...acquisition, bundle: { ...acquisition.bundle, path: "bundle.json" } },
		{ ...acquisition, checksums: { ...acquisition.checksums, path: "acquisition/SHA256SUMS.txt" } },
		{ ...acquisition, signature: "none" },
	]) expect(validates("generation", { ...generation, acquisition: changed })).toBe(false);
}, 60_000);
