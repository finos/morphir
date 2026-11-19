import { createHash } from "node:crypto";
import { mkdir, open, realpath, writeFile } from "node:fs/promises";
import path from "node:path";

export type Scale = "A" | "B";
export interface MaterializeOptions {
	readonly scale: Scale;
	readonly outputDir: string;
}
interface Dimensions {
	readonly moduleCount: number;
	readonly payloadCount: number;
	readonly payloadBytes: number;
}
/** Only injectable through the imported API. Production dimensions have no CLI overrides. */
export type TinyTestDimensions = Dimensions;

const DOCUMENT_LIMIT = 32 * 1024;
const STRING_TYPE = "morphir/SDK:string#string";
const FROZEN = path.resolve(import.meta.dir, "../spec/mck/bounded-generation/fixtures");
const EXPECTED_ARTIFACT_DIGEST: Readonly<Record<Scale, string>> = {
	A: "4647993318ded44552c1cfe273f96dfab83adefdf5d63849b6d4382ce7c6ee55",
	B: "4783e20057439e98e398b88a7cbf7f04299a0354324bcaa119971dd4dc523212",
};
const moduleName = (index: number) => `m${String(index).padStart(6, "0")}`;
const valueName = (index: number) => `order${String(index).padStart(6, "0")}`;

export function scaleDimensions(scale: Scale): Dimensions {
	if (scale !== "A" && scale !== "B") throw new Error("Scale must be A or B");
	return { moduleCount: scale === "A" ? 1024 : 2048, payloadCount: 64, payloadBytes: 16 * 1024 };
}

function dimensionsFor(scale: Scale, tiny?: TinyTestDimensions): Dimensions {
	const dimensions = scaleDimensions(scale);
	if (!tiny) return dimensions;
	if (![2, 3].includes(tiny.moduleCount)
		|| !Number.isInteger(tiny.payloadCount) || tiny.payloadCount < 2 || tiny.payloadCount > 64
		|| !Number.isInteger(tiny.payloadBytes) || tiny.payloadBytes < 32 || tiny.payloadBytes > 256) {
		throw new Error("Tiny tests require 2 or 3 modules, 2..64 payloads and 32..256 payload bytes");
	}
	return { ...tiny };
}

export function parseArguments(args: readonly string[]): MaterializeOptions {
	let scale: Scale | undefined;
	let outputDir: string | undefined;
	const usage = "Usage: bun tools/materialize-bounded-orders-scale.ts --scale A|B --output-dir <new-scratch-directory>";
	for (let index = 0; index < args.length; index += 2) {
		const flag = args[index];
		const value = args[index + 1];
		if (!value || value.startsWith("--")) throw new Error(usage);
		if (flag === "--scale" && scale === undefined && (value === "A" || value === "B")) scale = value;
		else if (flag === "--output-dir" && outputDir === undefined) outputDir = value;
		else throw new Error(usage);
	}
	if (!scale || !outputDir?.trim()) throw new Error(usage);
	return { scale, outputDir };
}

function within(root: string, candidate: string): boolean {
	const relative = path.relative(root, candidate);
	return relative === "" || (!path.isAbsolute(relative) && relative !== ".." && !relative.startsWith(`..${path.sep}`));
}

async function reserveDestination(outputDir: string): Promise<string> {
	if (!outputDir.trim()) throw new Error("An explicit output directory is required");
	const requested = path.resolve(outputDir);
	if (within(FROZEN, requested)) throw new Error("Cannot write inside the frozen fixture tree");
	// The caller supplies an existing scratch parent. Resolve junctions/symlinks before mkdir.
	const parent = await realpath(path.dirname(requested));
	const destination = path.join(parent, path.basename(requested));
	if (within(await realpath(FROZEN), destination)) throw new Error("Cannot write inside the frozen fixture tree");
	// Non-recursive creation refuses files, directories and symlinks, even an empty directory.
	await mkdir(destination);
	return destination;
}

function payload(module: number, value: number, bytes: number): string {
	return `${moduleName(module)}/${valueName(value)}:`.padEnd(bytes, "x");
}

/** An output oracle: no IR parsing, model reads, host invocation or accumulated artifact bytes. */
async function writeExpectedInventory(destination: string, dimensions: Dimensions) {
	const inventory = await open(path.join(destination, "expected-artifacts.json"), "wx");
	const digest = createHash("sha256");
	async function emit(text: string) {
		digest.update(text, "utf8");
		await inventory.writeFile(text, "utf8");
	}
	try {
		await emit("[");
		for (let module = 0; module < dimensions.moduleCount; module++) {
			const artifact = createHash("sha256");
			for (let value = 0; value < dimensions.payloadCount; value++) {
				artifact.update(payload(module, value, dimensions.payloadBytes), "utf8").update("\n");
			}
			artifact.update(payload(module, dimensions.payloadCount - 1, dimensions.payloadBytes), "utf8").update("\n");
			if (module) await emit(",");
			// These ASCII keys and paths are already in RFC 8785 order.
			await emit(JSON.stringify({ path: `orders/${moduleName(module)}.txt`, sha256: artifact.digest("hex") }));
		}
		await emit("]");
	} finally {
		await inventory.close();
	}
	return digest.digest("hex");
}

/** Writes only into a freshly reserved caller-owned destination. Leaves partial scratch on I/O failure. */
export async function materialize(options: MaterializeOptions, tiny?: TinyTestDimensions) {
	const dimensions = dimensionsFor(options.scale, tiny);
	const destination = await reserveDestination(options.outputDir);
	const expectedArtifactDigest = await writeExpectedInventory(destination, dimensions);
	if (!tiny && expectedArtifactDigest !== EXPECTED_ARTIFACT_DIGEST[options.scale]) {
		throw new Error(`Artifact inventory digest does not match the fixed scale ${options.scale} expectation`);
	}
	const modelRoot = path.join(destination, "model");
	await mkdir(modelRoot);
	let sourceBytes = 0;
	let maxDocumentBytes = 0;
	let documentCount = 0;
	const modelDigest = createHash("sha256");
	async function document(relative: string, content: unknown) {
		const bytes = Buffer.from(JSON.stringify(content) + "\n", "utf8");
		if (bytes.length > DOCUMENT_LIMIT) throw new Error(`Document exceeds ${DOCUMENT_LIMIT} bytes: ${relative}`);
		const file = path.join(modelRoot, relative);
		await mkdir(path.dirname(file), { recursive: true });
		await writeFile(file, bytes, { flag: "wx" });
		sourceBytes += bytes.length;
		maxDocumentBytes = Math.max(maxDocumentBytes, bytes.length);
		documentCount++;
		modelDigest.update(relative, "utf8").update("\0").update(bytes).update("\0");
	}
	// Source digest traversal is explicit and stable, independent of filesystem enumeration.
	await document("manifest.json", {
		formatVersion: 4, distribution: "Library", package: "acme/orders", pathBudget: 4000, dependencies: ["morphir/SDK"],
	});
	await document("deps/morphir/_sdk/@/string/module.json", { formatVersion: 4, path: "string", types: ["string"], values: [] });
	await document("deps/morphir/_sdk/@/string/string.type.json", { formatVersion: 4, name: "string", spec: { OpaqueTypeSpecification: {} } });
	const payloadNames = Array.from({ length: dimensions.payloadCount }, (_, index) => valueName(index));
	for (let module = 0; module < dimensions.moduleCount; module++) {
		const name = moduleName(module);
		const prefix = `pkg/acme/orders/${name}`;
		await document(`${prefix}/module.json`, { formatVersion: 4, path: name, types: [valueName(0)], values: [...payloadNames, "total-in-USD"] });
		await document(`${prefix}/${valueName(0)}.type.json`, {
			formatVersion: 4, name: valueName(0), def: { Public: { TypeAliasDefinition: { typeParams: [], typeExp: STRING_TYPE } } },
		});
		for (let value = 0; value < dimensions.payloadCount; value++) {
			await document(`${prefix}/${valueName(value)}.value.json`, {
				formatVersion: 4, name: valueName(value), def: { Public: { ExpressionBody: {
					inputTypes: {}, outputType: STRING_TYPE, body: { Literal: { StringLiteral: payload(module, value, dimensions.payloadBytes) } },
				} } },
			});
		}
		await document(`${prefix}/total-in-_usd.value.json`, {
			formatVersion: 4, name: "total-in-USD", def: { Public: { ExpressionBody: {
				inputTypes: {}, outputType: STRING_TYPE, body: { Reference: `acme/orders:${name}#${valueName(dimensions.payloadCount - 1)}` },
			} } },
		});
	}
	return {
		scale: options.scale, dimensions, pageSize: 16, documentLimitBytes: DOCUMENT_LIMIT,
		sourceBytes, maxDocumentBytes, documentCount, modelDigest: modelDigest.digest("hex"),
		artifactCount: dimensions.moduleCount,
		artifactBytes: dimensions.moduleCount * (dimensions.payloadCount + 1) * (dimensions.payloadBytes + 1),
		expectedArtifactDigest,
	};
}

if (import.meta.main) {
	try {
		console.log(JSON.stringify(await materialize(parseArguments(process.argv.slice(2))), null, 2));
	} catch (error) {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	}
}
