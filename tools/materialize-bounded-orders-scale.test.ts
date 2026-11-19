import { afterEach, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { materialize, parseArguments, scaleDimensions } from "./materialize-bounded-orders-scale.ts";

const scratch: string[] = [];
afterEach(async () => {
	for (const root of scratch.splice(0)) await rm(root, { recursive: true, force: true });
});
async function destination(name = "run") {
	const root = await mkdtemp(path.join(tmpdir(), "bounded-orders-scale-"));
	scratch.push(root);
	return path.join(root, name);
}
const hash = (bytes: string | Buffer) => createHash("sha256").update(bytes).digest("hex");
async function files(root: string, prefix = ""): Promise<string[]> {
	const result: string[] = [];
	for (const entry of await readdir(path.join(root, prefix), { withFileTypes: true })) {
		const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
		if (entry.isDirectory()) result.push(...await files(root, relative));
		else result.push(relative);
	}
	return result.sort();
}

test("production dimensions and explicit CLI selection, without running large materialization", () => {
	expect(scaleDimensions("A")).toEqual({ moduleCount: 1024, payloadCount: 64, payloadBytes: 16384 });
	expect(scaleDimensions("B")).toEqual({ moduleCount: 2048, payloadCount: 64, payloadBytes: 16384 });
	expect(parseArguments(["--scale", "B", "--output-dir", "scratch"])).toEqual({ scale: "B", outputDir: "scratch" });
	for (const args of [[], ["--scale", "A"], ["--output-dir", "x"], ["--scale", "C", "--output-dir", "x"], ["--scale", "A", "--output-dir", "x", "--modules", "2"], ["--scale", "A", "--scale", "B", "--output-dir", "x"]]) {
		expect(() => parseArguments(args)).toThrow();
	}
});

for (const moduleCount of [2, 3] as const) test(`tiny ${moduleCount}-module model is byte deterministic and independently matches full output hashes`, async () => {
	const first = await destination();
	const second = await destination();
	const tiny = { moduleCount, payloadCount: 64, payloadBytes: 48 };
	const a = await materialize({ scale: "A", outputDir: first }, tiny);
	const b = await materialize({ scale: "A", outputDir: second }, tiny);
	expect(a).toEqual(b);
	const names = await files(first);
	expect(names).toEqual(await files(second));
	for (const name of names) expect(await readFile(path.join(first, name))).toEqual(await readFile(path.join(second, name)));
	const independentInventory: { path: string; sha256: string }[] = [];
	const inventory = JSON.parse(await readFile(path.join(first, "expected-artifacts.json"), "utf8"));
	expect(inventory).toHaveLength(moduleCount);
	expect(hash(await readFile(path.join(first, "expected-artifacts.json")))).toBe(a.expectedArtifactDigest);
	let bytes = 0;
	let maximum = 0;
	for (const name of await files(path.join(first, "model"))) {
		const size = (await stat(path.join(first, "model", name))).size;
		bytes += size;
		maximum = Math.max(maximum, size);
	}
	expect(a.sourceBytes).toBe(bytes);
	expect(a.maxDocumentBytes).toBe(maximum);
	expect(maximum).toBeLessThanOrEqual(32768);
	for (let m = 0; m < moduleCount; m++) {
		const module = `m${String(m).padStart(6, "0")}`;
		const root = path.join(first, "model/pkg/acme/orders", module);
		const manifest = JSON.parse(await readFile(path.join(root, "module.json"), "utf8"));
		expect(manifest.types).toEqual(["order000000"]);
		const members = [...manifest.types.map((name: string) => ({ kind: "type", name })), ...manifest.values.map((name: string) => ({ kind: "value", name }))];
		expect(members.slice(64)).toEqual([{ kind: "value", name: "order000063" }, { kind: "value", name: "total-in-USD" }]);
		const reference = JSON.parse(await readFile(path.join(root, "total-in-_usd.value.json"), "utf8")).def.Public.ExpressionBody.body.Reference;
		expect(reference).toBe(`acme/orders:${module}#order000063`);
		const observed: string[] = [];
		const independent: string[] = [];
		for (let v = 0; v < 64; v++) {
			const name = `order${String(v).padStart(6, "0")}`;
			observed.push(JSON.parse(await readFile(path.join(root, `${name}.value.json`), "utf8")).def.Public.ExpressionBody.body.Literal.StringLiteral);
			independent.push(`${module}/${name}:`.padEnd(48, "x"));
		}
		observed.push(JSON.parse(await readFile(path.join(root, `${reference.split("#")[1]}.value.json`), "utf8")).def.Public.ExpressionBody.body.Literal.StringLiteral);
		independent.push(independent[63]!);
		const expected = independent.join("\n") + "\n";
		expect(observed.join("\n") + "\n").toBe(expected);
		independentInventory.push({ path: `orders/${module}.txt`, sha256: hash(expected) });
		expect(inventory[m]).toEqual(independentInventory[m]);
		// Redirecting the final reference, changing a body or dropping the final page fails the full hash.
		for (const changed of [observed.slice(0, 63), [...observed.slice(0, 64), observed[0]!], ["changed", ...observed.slice(1)]]) {
			expect(hash(changed.join("\n") + "\n")).not.toBe(inventory[m].sha256);
		}
	}
	expect(a.expectedArtifactDigest).toBe(hash(JSON.stringify(independentInventory)));
	expect(a.artifactBytes).toBe(moduleCount * 65 * 49);
});

test("refuses existing destinations, frozen fixture paths and non-tiny injection before writing", async () => {
	const out = await destination();
	const tiny = { moduleCount: 2, payloadCount: 2, payloadBytes: 32 } as const;
	await materialize({ scale: "A", outputDir: out }, tiny);
	await writeFile(path.join(out, "sentinel"), "keep");
	await expect(materialize({ scale: "A", outputDir: out }, tiny)).rejects.toThrow();
	expect(await readFile(path.join(out, "sentinel"), "utf8")).toBe("keep");
	await expect(materialize({ scale: "A", outputDir: path.resolve(import.meta.dir, "../spec/mck/bounded-generation/fixtures/new-scale") }, tiny)).rejects.toThrow(/frozen/i);
	await expect(materialize({ scale: "A", outputDir: await destination() }, { ...tiny, moduleCount: 1024 })).rejects.toThrow(/tiny/i);
});
