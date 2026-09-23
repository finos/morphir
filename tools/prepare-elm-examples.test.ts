import { test, expect } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { prepareElmExamples } from "./prepare-elm-examples.ts";

test("prepare local repositories without changing project configuration", () => {
	const root = mkdtempSync(join(tmpdir(), "morphir-elm-prep-"));
	try {
		const binary = join(root, "elm-extension");
		const bytes = Buffer.from([0, 1, 254, 255]);
		writeFileSync(binary, bytes);
		const project = join(root, "examples/morphir-elm-compat");
		mkdirSync(project, { recursive: true });
		writeFileSync(join(project, "morphir.json"), '{"name":"Existing"}');
		prepareElmExamples(root, binary, "0.3.1");
		for (const name of ["morphir-elm-compat", "elm/single-file-functions", "elm/classic-json"]) {
			const repo = join(root, "examples", name, ".itest/elm");
			const record = JSON.parse(readFileSync(join(repo, "extensions/morphir-elm.jsonl"), "utf8"));
			expect(record.id).toBe("morphir-elm");
			expect(record.version).toBe("0.3.1");
			expect(record.capabilities).toEqual(["frontend", "workspace"]);
			const artifact = record.artifacts[0];
			expect(artifact.sha256).toBe(createHash("sha256").update(bytes).digest("hex"));
			expect(artifact.platform).toEqual({
				os: process.platform === "darwin" ? "macos" : process.platform === "win32" ? "windows" : process.platform,
				arch: process.arch === "arm64" ? "aarch64" : process.arch === "x64" ? "x86_64" : process.arch,
			});
			expect(readFileSync(join(repo, artifact.source.path))).toEqual(bytes);
		}
		expect(readFileSync(join(project, "morphir.json"), "utf8")).toBe('{"name":"Existing"}');
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test("reject unsupported releases and empty executables", () => {
	const root = mkdtempSync(join(tmpdir(), "morphir-elm-prep-"));
	try {
		const binary = join(root, "elm-extension");
		writeFileSync(binary, "");
		expect(() => prepareElmExamples(root, binary, "0.2.0")).toThrow("require morphir-elm extension 0.3.1");
		expect(() => prepareElmExamples(root, binary, "0.3.1")).toThrow("executable is empty");
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});
