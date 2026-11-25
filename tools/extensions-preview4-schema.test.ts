// Schema integrity and contract checks for extensions/0.1.0-preview.4 (adds capabilities.modelAccess while preserving 0.1.0-preview.3 byte-for-byte).
import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const preview3Root = "website/static/schemas/extensions/0.1.0-preview.3";
const preview4Root = "website/static/schemas/extensions/0.1.0-preview.4";
const preview4Prefix = "https://morphir.finos.org/schemas/extensions/0.1.0-preview.4/";

const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

function validateDocument(schemaRoot: string, schemaFile: string, document: unknown): boolean {
	const temp = mkdtempSync(join(tmpdir(), "morphir-extensions-preview4-"));
	try {
		const input = join(temp, "doc.json");
		writeFileSync(input, JSON.stringify(document));
		const result = spawnSync("jsonschema", ["validate", join(schemaRoot, schemaFile), input, "-r", schemaRoot], {
			encoding: "utf8",
			windowsHide: true,
		});
		expect(result.error).toBeUndefined();
		return result.status === 0;
	} finally {
		rmSync(temp, { recursive: true, force: true });
	}
}

function sampleModelAccess() {
	return {
		tuples: [
			{
				protocolVersion: "0.2.0-draft.2",
				accessVersion: "0.1.0-draft.1",
				operation: "morphir.backend.generateModel",
				irVersion: "4.0.0",
				profile: "morphir-ir",
				codec: "morphir-json",
				layout: "document-tree",
				contextualEncoding: "plain",
			},
		],
		limits: {
			maxFrameBytes: 65536,
			maxEncodedBytesPerExchange: 16384,
			maxDecodedBytesPerExchange: 16384,
			maxDocumentsPerBatch: 16,
			maxDepth: 64,
			maxNodes: 2048,
			maxDiagnosticsPerExchange: 32,
			maxOutstandingRequests: 8,
			maxGuestStateBytes: 2097152,
			maxHostCacheBytes: 1048576,
			maxArtifactChunkBytes: 16384,
			maxArtifactBytes: 1048576,
			maxTotalArtifactBytes: 4194304,
			maxSessionDiskBytes: 8388608,
			maxSessionWorkUnits: 4096,
			maxRounds: 64,
			maxCallMilliseconds: 5000,
			maxSessionMilliseconds: 30000,
		},
	};
}

describe("extensions/0.1.0-preview.4 schemas", () => {
	test("published 0.1.0-preview.3 schemas remain byte-for-byte frozen", () => {
		const expectedHashes: Record<string, string> = {
			"catalog.schema.json": "e9e5274032e72715d66f64912cd1cabf52c464a862f2769d91bd9f296126d7da",
			"claims.schema.json": "9e10c26d654fd02e3ea6bdf84cd9375dff28b2e15a9c10e7d400a969ee598fb9",
			"index-record.schema.json": "7fb4a8fe6ed5edb51b9dd962e1cfce47df52ce635b79919a2bd1e71818ed6d18",
			"journal.schema.json": "033ee53c5c70c54324bdd326cc43105decb8a55ee2bc32272da3d6bf00eed399",
			"lock.schema.json": "f33e8fb9af7fa6db4cf53816a9c1b514921ccda42cd3d2155d9d3f50e2296e59",
			"release.schema.json": "3f8647d89525414563714838c3326a7960f6bda3bdb6948959bc5b6fb130027e",
			"repositories.schema.json": "e6247986f7448c9b63ae318606645845e056a1573dfff46e7c68ee8627743fd5",
		};
		const files = readdirSync(preview3Root).filter((n) => n.endsWith(".schema.json")).sort();
		expect(files).toEqual(Object.keys(expectedHashes).sort());
		for (const [file, hash] of Object.entries(expectedHashes)) {
			expect(sha256(readFileSync(join(preview3Root, file))), file).toBe(hash);
		}
	});

	test("all seven 0.1.0-preview.4 schemas validate against metaschema and keep recursive open/closed policies", () => {
		const schemas = readdirSync(preview4Root).filter((n) => n.endsWith(".schema.json")).sort();
		expect(schemas.length).toBe(7);

		const visit = (schema: any, open: boolean, at: string, seen = new Set<string>()) => {
			if (!schema || typeof schema !== "object") return;
			if (schema.$ref) {
				if (seen.has(schema.$ref)) return;
				expect(schema.$ref).toStartWith(preview4Prefix);
				const next = new Set(seen).add(schema.$ref);
				const [url, fragment] = schema.$ref.split("#");
				let target = JSON.parse(readFileSync(join(preview4Root, url.split("/").pop()), "utf8"));
				for (const key of (fragment ?? "").split("/").filter(Boolean)) target = target[key];
				visit(target, open, at, next);
			}
			if (schema.type === "object") expect(schema.additionalProperties, at).toBe(open);
			for (const [key, value] of Object.entries(schema.properties ?? {})) visit(value, open, `${at}.${key}`, seen);
			if (schema.items) visit(schema.items, open, `${at}[]`, seen);
			for (const key of ["allOf", "anyOf", "oneOf"]) for (const value of schema[key] ?? []) visit(value, open, at, seen);
			for (const key of ["if", "then", "else"]) visit(schema[key], open, at, seen);
		};

		for (const name of schemas) {
			const schema = JSON.parse(readFileSync(join(preview4Root, name), "utf8"));
			expect(schema.$id).toBe(`${preview4Prefix}${name}`);
			expect(schema.properties.$schema.const).toBe(`${preview4Prefix}${name}`);
			const result = spawnSync("jsonschema", ["metaschema", join(preview4Root, name)], {
				encoding: "utf8",
				windowsHide: true,
			});
			expect(result.status, `${name}: ${result.stdout} ${result.stderr}`).toBe(0);
			visit(schema, !["lock.schema.json", "journal.schema.json", "repositories.schema.json"].includes(name), name);
		}

		const withoutPolicy = (s: any): any =>
			Array.isArray(s)
				? s.map(withoutPolicy)
				: s && typeof s === "object"
					? Object.fromEntries(
						Object.entries(s)
							.filter(([k]) => k !== "additionalProperties")
							.map(([k, v]) => [k, withoutPolicy(v)]),
					)
					: s;
		const claims = JSON.parse(readFileSync(join(preview4Root, "claims.schema.json"), "utf8"));
		expect(withoutPolicy(claims.$defs.closedEmbedded)).toEqual(withoutPolicy(claims.$defs.embedded));
	});

	test("lock and claims validate capabilities.modelAccess under 0.1.0-preview.4 and reject it under 0.1.0-preview.3", () => {
		const embeddedClaims = (withExtra: boolean) => ({
			protocolVersions: ["0.2.0-draft.2", "0.2.0-draft.1"],
			extension: {
				id: "org.finos.morphir.fsharp-backend",
				name: "F# Backend",
				version: "0.5.0",
				types: ["backend"],
			},
			capabilities: {
				backend: { targets: ["fsharp"], irVersions: ["4.0.0"], generate: true },
				modelAccess: withExtra ? { ...sampleModelAccess(), extraField: true } : sampleModelAccess(),
			},
		});

		const makeLock = (prefix: string, withExtra: boolean) => ({
			$schema: `${prefix}lock.schema.json`,
			selection: { kind: "exact", value: "0.5.0" },
			extensionId: "org.finos.morphir.fsharp-backend",
			name: "F# Backend",
			version: "0.5.0",
			index: {
				kind: "local-directory",
				identity: "/repo",
				revision: "a".repeat(64),
				claims: embeddedClaims(withExtra),
			},
			source: { kind: "local-file", path: "artifacts/fsharp-backend.wasm" },
			runtime: "wasm",
			args: [],
			digest: "b".repeat(64),
			capabilities: ["backend"],
			mepVersions: ["0.2.0-draft.2", "0.2.0-draft.1"],
			backend: { targets: ["fsharp"], irVersions: ["4.0.0"], generate: true },
			executable: false,
		});

		const standaloneClaims = {
			$schema: `${preview4Prefix}claims.schema.json`,
			...embeddedClaims(true),
		};

		const catalog = {
			$schema: `${preview4Prefix}catalog.schema.json`,
			extensions: [
				{
					extensionId: "org.finos.morphir.fsharp-backend",
					name: "F# Backend",
					version: "0.5.0",
					storePath: "store/extensions/sha256/" + "c".repeat(64) + "/fsharp-backend.wasm",
					index: { kind: "local-directory", identity: "/repo", revision: "a".repeat(64) },
					claims: embeddedClaims(false),
					claimCheck: "unchecked",
					runtime: "wasm",
					args: [],
					digest: "b".repeat(64),
					capabilities: ["backend"],
					mepVersions: ["0.2.0-draft.2", "0.2.0-draft.1"],
					backend: { targets: ["fsharp"], irVersions: ["4.0.0"], generate: true },
					executable: false,
				},
			],
		};

		expect(validateDocument(preview4Root, "lock.schema.json", makeLock(preview4Prefix, false))).toBe(true);
		expect(validateDocument(preview4Root, "lock.schema.json", makeLock(preview4Prefix, true))).toBe(false);
		expect(validateDocument(preview3Root, "lock.schema.json", makeLock("https://morphir.finos.org/schemas/extensions/0.1.0-preview.3/", false))).toBe(false);
		expect(validateDocument(preview4Root, "claims.schema.json", standaloneClaims)).toBe(true);
		expect(validateDocument(preview4Root, "catalog.schema.json", catalog)).toBe(true);

		const makeWithLimits = (overrides: Record<string, number>) => {
			const claims = embeddedClaims(false);
			return {
				...claims,
				capabilities: {
					...claims.capabilities,
					modelAccess: {
						...claims.capabilities.modelAccess,
						limits: { ...claims.capabilities.modelAccess.limits, ...overrides },
					},
				},
			};
		};

		const validBoundary = makeWithLimits({
			maxFrameBytes: 2147483647,
			maxSessionMilliseconds: 2147483647,
			maxArtifactBytes: 9007199254740991,
			maxSessionWorkUnits: 9007199254740991,
		});
		const overflowFrame = makeWithLimits({ maxFrameBytes: 2147483648 });
		const overflowSessionMs = makeWithLimits({ maxSessionMilliseconds: 2147483648 });
		const overflowArtifactBytes = makeWithLimits({ maxArtifactBytes: 9007199254740992 });

		const wrapStandalone = (claims: ReturnType<typeof makeWithLimits>) => ({
			$schema: `${preview4Prefix}claims.schema.json`,
			...claims,
		});
		const wrapCatalog = (claims: ReturnType<typeof makeWithLimits>) => ({
			...catalog,
			extensions: [{ ...catalog.extensions[0], claims }],
		});
		const wrapLock = (claims: ReturnType<typeof makeWithLimits>) => {
			const baseLock = makeLock(preview4Prefix, false);
			return {
				...baseLock,
				index: { ...baseLock.index, claims },
			};
		};

		expect(validateDocument(preview4Root, "claims.schema.json", wrapStandalone(validBoundary))).toBe(true);
		expect(validateDocument(preview4Root, "catalog.schema.json", wrapCatalog(validBoundary))).toBe(true);
		expect(validateDocument(preview4Root, "lock.schema.json", wrapLock(validBoundary))).toBe(true);

		for (const invalid of [overflowFrame, overflowSessionMs, overflowArtifactBytes]) {
			expect(validateDocument(preview4Root, "claims.schema.json", wrapStandalone(invalid))).toBe(false);
			expect(validateDocument(preview4Root, "catalog.schema.json", wrapCatalog(invalid))).toBe(false);
			expect(validateDocument(preview4Root, "lock.schema.json", wrapLock(invalid))).toBe(false);
		}
	});
});
