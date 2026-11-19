// Tiny equivalent of d2804e50's materializer. This is a guest/shim test, not host qualification.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dir, "..");
const hash = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");
const opaque = () => randomUUID() + '–"\\';
const clang = Bun.which("clang");
const linker = clang && path.join(path.dirname(clang), process.platform === "win32" ? "wasm-ld.exe" : "wasm-ld");
const hasToolchain = linker !== null && existsSync(linker);
const scaleTest = test.skipIf(!hasToolchain);
let wasm: WebAssembly.Module;
let buildDirectory: string | undefined;
beforeAll(() => {
	if (!hasToolchain || !clang || !linker) return;
	const scratch = path.join(root, ".dev");
	mkdirSync(scratch, { recursive: true });
	buildDirectory = mkdtempSync(path.join(scratch, "scale-test-"));
	const object = path.join(buildDirectory, "guest.o");
	const binary = path.join(buildDirectory, "guest.wasm");
	const build = Bun.spawnSync([clang, "--target=wasm32", "-O2", "-fno-builtin", "-nostdlib", "-Wall", "-Wextra", "-Werror", "-c",
		"-o", object, path.join(root, "spec/mck/bounded-generation/scale-guest.c")]);
	expect(build.exitCode, new TextDecoder().decode(build.stderr)).toBe(0);
	const linked = Bun.spawnSync([linker, "--no-entry", "--export-memory", "-z", "stack-size=262144", "--initial-memory=1048576", "--max-memory=1048576",
		"-o", binary, object]);
	expect(linked.exitCode, new TextDecoder().decode(linked.stderr)).toBe(0);
	wasm = new WebAssembly.Module(readFileSync(binary));
	expect(WebAssembly.Module.imports(wasm).map(entry => `${entry.module}.${entry.name}`).sort()).toEqual(
		["alloc", "input_length", "input_load_u8", "output_set", "store_u8"].map(name => `extism:host/env.${name}`).sort());
	expect(WebAssembly.Module.exports(wasm).map(entry => entry.name).sort()).toEqual(["handle", "memory"]);
});
afterAll(() => {
	if (buildDirectory) rmSync(buildDirectory, { recursive: true, force: true });
});

function guest() {
	let input = Buffer.alloc(0), output = Buffer.alloc(0), kernel = Buffer.alloc(262144), next = 77;
	const instance = new WebAssembly.Instance(wasm, { "extism:host/env": {
		input_length: () => BigInt(input.length), input_load_u8: (at: bigint) => input[Number(at)],
		alloc: (length: bigint) => { const at = next; next += Number(length) + 12; return BigInt(at); },
		store_u8: (at: bigint, value: number) => { kernel[Number(at)] = value; },
		output_set: (at: bigint, length: bigint) => { output = Buffer.from(kernel.subarray(Number(at), Number(at + length))); },
	} });
	expect((instance.exports.memory as WebAssembly.Memory).buffer.byteLength).toBe(1048576);
	let id = 0;
	return (method: string, params?: unknown) => {
		input = Buffer.from(JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }));
		next = 77; output = Buffer.alloc(0);
		expect((instance.exports.handle as () => number)()).toBe(0);
		const reply = JSON.parse(output.toString());
		expect((instance.exports.memory as WebAssembly.Memory).buffer.byteLength).toBe(1048576);
		expect(reply.id).toBe(id);
		return reply;
	};
}
const operation = "morphir.backend.generateModel";
const tuple = { protocolVersion: "0.2.0-draft.2", accessVersion: "0.1.0-draft.1", operation,
	irVersion: "4.0.0", profile: "morphir-ir", codec: "morphir-json", layout: "document-tree", contextualEncoding: "plain" };
const limits = Object.fromEntries([
	"maxFrameBytes", "maxEncodedBytesPerExchange", "maxDecodedBytesPerExchange", "maxDocumentsPerBatch", "maxDepth", "maxNodes",
	"maxDiagnosticsPerExchange", "maxOutstandingRequests", "maxGuestStateBytes", "maxHostCacheBytes", "maxArtifactChunkBytes",
	"maxArtifactBytes", "maxTotalArtifactBytes", "maxSessionDiskBytes", "maxSessionWorkUnits", "maxRounds", "maxCallMilliseconds", "maxSessionMilliseconds",
].map(key => [key, key === "maxDepth" ? 64 : 2_147_483_647]));
limits.maxTotalArtifactBytes = 2_181_171_200;
limits.maxSessionDiskBytes = 4_294_967_296;
limits.maxHostCacheBytes = 16 * 1024 * 1024;
const pad = (n: number) => String(n).padStart(6, "0");
const payload = (m: number, v: number) => `m${pad(m)}/order${pad(v)}:`.padEnd(48, "x");

function run(control = "valid", maxRounds = limits.maxRounds!) {
	const call = guest(), sessionId = opaque(), snapshotId = opaque();
	const admission = call("morphir.initialize", { protocolVersions: [tuple.protocolVersion], host: { name: "tiny-shim", version: "0.1.0" }, modelAccess: { tuples: [tuple], limits: { ...limits, maxRounds } } }).result;
	const active = admission.capabilities.modelAccess.limits;
	expect(active.maxTotalArtifactBytes).toBe(limits.maxTotalArtifactBytes!);
	expect(active.maxSessionDiskBytes).toBe(limits.maxSessionDiskBytes!);
	expect(active.maxHostCacheBytes).toBe(limits.maxHostCacheBytes!);
	const pages = new Map<string, any[]>(), documents = new Map<string, any>();
	const roots: any[] = [], rootCursors = new Set<string>(), memberCursors = new Set<string>();
	const stringType = "morphir/SDK:string#string";
	for (let m = 0; m < 3; m++) {
		const modulePath = `m${pad(m)}`, memberSelection = opaque(), members: any[] = [];
		const identity = () => ({ documentId: opaque(), packageName: "acme/orders", modulePath, role: "definition" });
		roots.push({ module: { ...identity(), memberSelection } });
		const add = (kind: string, name: string, def: any) => {
			const item = { ...identity(), name }; members.push({ [kind]: item });
			documents.set(item.documentId, { formatVersion: 4, name, def: { Public: def } });
		};
		add("type", "order000000", { TypeAliasDefinition: { typeParams: [], typeExp: stringType } });
		for (let v = 0; v < 64; v++) add("value", `order${pad(v)}`, { ExpressionBody: { inputTypes: {}, outputType: stringType,
			body: { Literal: { StringLiteral: payload(m, v) } } } });
		add("value", "total-in-USD", { ExpressionBody: { inputTypes: {}, outputType: stringType, body: { Reference: `acme/orders:${modulePath}#order${pad(control === "redirect" ? 0 : 63)}` } } });
		if (control === "late" && m === 2) documents.get(members[64].value.documentId).def.Public.ExpressionBody.body.Literal.StringLiteral = "late mutation";
		if (control === "large-document" && m === 2) documents.get(members[64].value.documentId).def.Public.ExpressionBody.body.Literal.StringLiteral = payload(m, 63).padEnd(16384, "x");
		if (control === "signature") documents.get(members[2].value.documentId).def.Public.ExpressionBody.outputType = "wrong";
		if (control === "alias") documents.get(members[0].type.documentId).def.Public.TypeAliasDefinition.typeExp = "wrong";
		if (control === "missing-reference") documents.get(members[65].value.documentId).def.Public.ExpressionBody.body.Reference = `acme/orders:${modulePath}#absent`;
		if (control === "reordered") [members[0], members[1]] = [members[1], members[0]];
		if (control === "missing") members.splice(64);
		pages.set(memberSelection, members);
	}
	roots.splice(1, 0, { module: { documentId: opaque(), packageName: "morphir/SDK", modulePath: "string", role: "specification" } });
	pages.set("root", roots);
	// Cursor ownership lives in the shim. The guest must echo these exact tokens.
	const cursors = new Map<string, { selection: string; at: number }>();
	let step = call(operation + ".start", { sessionId, snapshot: { snapshotId, modelId: "acme/orders", revision: opaque(), scope: opaque(), contextDigest: "1".repeat(64) }, input: tuple, target: "text", options: {}, requiredGuarantees: [], limits: active }).result;
	const artifacts = new Map<string, Buffer>(), closed = new Set<string>(), requests = new Set<string>();
	let error: any, retried = false;
	for (let count = 0; count < 2000; count++) {
		for (const chunk of step.artifacts ?? []) {
			expect(closed.has(chunk.path)).toBe(false);
			const previous = artifacts.get(chunk.path) ?? Buffer.alloc(0), bytes = Buffer.from(chunk.content, "base64");
			expect(chunk.offset).toBe(previous.length); expect(chunk.decodedByteLength).toBe(bytes.length); expect(chunk.sha256).toBe(hash(bytes));
			artifacts.set(chunk.path, Buffer.concat([previous, bytes])); if (chunk.end) closed.add(chunk.path);
		}
		if (step.state !== "continue") break;
		const [request] = step.requests; expect(requests.has(request.requestId)).toBe(false); requests.add(request.requestId);
		let delivery: any = { requestId: request.requestId, kind: request.kind, snapshotId };
		if (request.kind === "inventory") {
			expect(request.pageSize).toBe(16);
			const at = request.cursor ? cursors.get(request.cursor) : { selection: request.selection, at: 0 };
			expect(at?.selection).toBe(request.selection);
			const entries = pages.get(request.selection)!;
			const end = Math.min(at!.at + (request.selection === "root" ? 2 : 16), entries.length);
			delivery.entries = entries.slice(at!.at, end);
			if (end < entries.length) { delivery.nextCursor = opaque(); cursors.set(delivery.nextCursor, { selection: request.selection, at: end });
				(request.selection === "root" ? rootCursors : memberCursors).add(delivery.nextCursor); }
		} else {
			const bytes = Buffer.from(JSON.stringify(documents.get(request.documentId)) + "\n");
			delivery = { ...delivery, documentId: request.documentId, decodedByteLength: bytes.length, sha256: hash(bytes), content: bytes.toString("base64") };
			if (control === "identity" && !retried) {
				for (const bad of [{ ...delivery, documentId: opaque() }, { ...delivery, requestId: opaque() }, { ...delivery, snapshotId: opaque() }, { ...delivery, decodedByteLength: delivery.decodedByteLength + 1 }, { ...delivery, sha256: "0".repeat(64) }, { ...delivery, content: delivery.content + "=" }])
					expect(call(operation + ".advance", { sessionId, round: step.round, deliveries: [bad] }).error.code).toBe(-32602);
				expect(call(operation + ".advance", { sessionId, round: step.round - 1, deliveries: [delivery] }).error.code).toBe(-32602);
				retried = true;
			}
		}
		const response = call(operation + ".advance", { sessionId, round: step.round, deliveries: [delivery] });
		if (response.error) { error = response.error; break; } step = response.result;
	}
	return { artifacts, closed, step, error, rootCursors, memberCursors, call, sessionId };
}

for (const control of ["valid", "identity", "redirect", "late", "large-document"]) scaleTest(`scale guest streams exact tiny output: ${control}`, () => {
	const result = run(control);
	expect(result.error).toBeUndefined(); expect(result.step.state).toBe("complete");
	expect([...result.closed]).toEqual([0, 1, 2].map(m => `orders/m${pad(m)}.txt`));
	expect(result.rootCursors.size).toBeGreaterThan(0); expect(result.memberCursors.size).toBeGreaterThanOrEqual(12);
	for (let m = 0; m < 3; m++) {
		const lines = Array.from({ length: 64 }, (_, v) => m === 2 && v === 63
			? control === "late" ? "late mutation" : control === "large-document" ? payload(m, v).padEnd(16384, "x") : payload(m, v)
			: payload(m, v));
		lines.push(control === "redirect" ? payload(m, 0) : lines[63]!);
		const bytes = result.artifacts.get(`orders/m${pad(m)}.txt`)!;
		expect(bytes).toEqual(Buffer.from(lines.join("\n") + "\n"));
		if (control === "redirect" || control === "late" && m === 2) expect(hash(bytes)).not.toBe(hash(Buffer.from([...Array.from({ length: 64 }, (_, v) => payload(m, v)), payload(m, 63)].join("\n") + "\n")));
	}
	expect(result.call(operation + ".advance", { sessionId: result.sessionId, round: 1, deliveries: [] }).error.code).toBe(-32602);
});
for (const control of ["missing", "signature", "alias", "missing-reference", "reordered"]) scaleTest(`scale guest rejects ${control}`, () => {
	const result = run(control); expect(result.error?.code).toBe(-32602); expect(result.closed.size).toBe(0);
});

scaleTest("the round ceiling permits completion but refuses a continuation", () => {
	const finalRound = 2 + 3 * 77;
	const exact = run("valid", finalRound);
	expect(exact.error).toBeUndefined();
	expect(exact.step.state).toBe("complete");
	expect(exact.closed.size).toBe(3);
	const expected = Array.from({ length: 64 }, (_, value) => payload(2, value));
	expected.push(expected[63]!);
	expect(exact.artifacts.get("orders/m000002.txt")).toEqual(Buffer.from(expected.join("\n") + "\n"));

	const short = run("valid", finalRound - 1);
	expect(short.error?.code).toBe(-32602);
	expect(short.step.round).toBe(finalRound - 1);
	expect(short.closed.size).toBe(2);
});
