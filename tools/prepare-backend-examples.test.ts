import { expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { prepareBackendExamples } from "./prepare-backend-examples.ts";

function fixture(run: (root: string, bundles: string, bytes: Buffer<ArrayBuffer>) => void) {
	const root = mkdtempSync(join(tmpdir(), "morphir-backend-prep-"));
	try {
		const bundles = join(root, "downloads");
		const bytes = Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]);
		const sha256 = createHash("sha256").update(bytes).digest("hex");
		mkdirSync(join(root, ".config"));
		writeFileSync(join(root, ".config/published-extension-bundles.toml"),
			["avro", "openapi"].map(id => `[bundles.${id}]\ntag = "extension/${id}/v0.1.0"\nartifact = "${id}-guest"\nsha256 = "${sha256}"\n`).join("\n"));
		for (const id of ["avro", "openapi"]) {
			mkdirSync(join(bundles, id), { recursive: true });
			writeFileSync(join(bundles, id, `${id}-guest.wasm`), bytes);
			writeFileSync(join(bundles, id, `${id}-guest.wasm.sha256`), `${sha256}  ${id}-guest.wasm\n`);
			writeFileSync(join(bundles, id, "release.json"), JSON.stringify({ id: `morphir-${id}`, version: "0.1.0" }));
		}
		run(root, bundles, bytes);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

test("stage pinned backend bundles verbatim and replace stale fixture files", () => fixture((root, bundles, bytes) => {
	const project = join(root, "examples/backends/avro");
	mkdirSync(join(project, ".itest/bundle"), { recursive: true });
	writeFileSync(join(project, ".itest/bundle/stale.wasm"), "old");
	writeFileSync(join(project, "morphir.toml"), "keep project config");
	prepareBackendExamples(root, bundles);
	for (const id of ["avro", "openapi"]) {
		const staged = join(root, "examples/backends", id, ".itest/bundle");
		expect(readFileSync(join(staged, `${id}-guest.wasm`))).toEqual(bytes);
		for (const name of ["release.json", `${id}-guest.wasm.sha256`]) {
			expect(readFileSync(join(staged, name))).toEqual(readFileSync(join(bundles, id, name)));
		}
	}
	expect(existsSync(join(project, ".itest/bundle/stale.wasm"))).toBe(false);
	expect(readFileSync(join(project, "morphir.toml"), "utf8")).toBe("keep project config");
}));

test("reject a digest mismatch before staging either bundle", () => fixture((root, bundles) => {
	writeFileSync(join(bundles, "openapi/openapi-guest.wasm"), "corrupt");
	expect(() => prepareBackendExamples(root, bundles)).toThrow("does not match the pinned sha256");
	expect(existsSync(join(root, "examples"))).toBe(false);
}));

test("reject a missing descriptor before staging either bundle", () => fixture((root, bundles) => {
	rmSync(join(bundles, "openapi/release.json"));
	expect(() => prepareBackendExamples(root, bundles)).toThrow();
	expect(existsSync(join(root, "examples"))).toBe(false);
}));

test("stage both bundles beside the v4 rejection scenarios", () => fixture((root, bundles) => {
	prepareBackendExamples(root, bundles);
	for (const id of ["avro", "openapi"]) {
		const staged = join(root, "examples/backends/v4-published-rejection/.itest", id);
		for (const name of [`${id}-guest.wasm`, `${id}-guest.wasm.sha256`, "release.json"]) {
			expect(readFileSync(join(staged, name))).toEqual(readFileSync(join(bundles, id, name)));
		}
	}
}));
