import { afterEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { contractDrift } from "./check-mck-contract-copies";

const workspaces: string[] = [];
afterEach(() => {
	for (const root of workspaces.splice(0)) rmSync(root, { recursive: true, force: true });
});

function fixture() {
	const root = mkdtempSync(path.join(os.tmpdir(), "mck-contract-copies-"));
	workspaces.push(root);
	const copies = path.join(root, "spec/ir/mck");
	const originals = path.join(root, "ecosystem/morphir-typescript/packages/mck");
	for (const directory of [copies, originals]) {
		mkdirSync(directory, { recursive: true });
		for (const name of ["protocol.schema.json", "protocol.example.json"]) {
			writeFileSync(path.join(directory, name), "same bytes\n");
		}
	}
	return { root, copies, originals };
}

test("accepts identical copies without parsing or validating JSON", () => {
	expect(contractDrift(fixture().root)).toEqual([]);
});

test("rejects byte drift in either contract even when JSON values match", () => {
	for (const name of ["protocol.schema.json", "protocol.example.json"]) {
		const { root, copies, originals } = fixture();
		writeFileSync(path.join(copies, name), "{}\n");
		writeFileSync(path.join(originals, name), "{}");
		expect(contractDrift(root)).toEqual([
			`${name}: differs from ${path.join("ecosystem/morphir-typescript/packages/mck", name)}; re-copy it`,
		]);
	}
});

test("rejects a missing example original", () => {
	const { root, originals } = fixture();
	rmSync(path.join(originals, "protocol.example.json"));
	expect(contractDrift(root)).toEqual(["protocol.example.json: the submodule original is missing"]);
});

test("preserves the optional comparison when the submodule is absent", () => {
	const { root, originals } = fixture();
	rmSync(originals, { recursive: true });
	expect(contractDrift(root)).toEqual([]);
});
