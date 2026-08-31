import { afterEach, describe, expect, test } from "bun:test";
import {
	mkdtempSync,
	mkdirSync,
	readFileSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import {
	assertCleanSource,
	collectWebAssets,
	replaceVendoredAssets,
	validateSourceCommit,
} from "./vendor-morphir-web";

const temporaryDirectories: string[] = [];

const temporaryDirectory = (): string => {
	const directory = mkdtempSync(path.join(tmpdir(), "morphir-web-vendor-test-"));
	temporaryDirectories.push(directory);
	return directory;
};

afterEach(() => {
	for (const directory of temporaryDirectories.splice(0)) {
		rmSync(directory, { force: true, recursive: true });
	}
});

describe("morphir-web vendoring", () => {
	test("accepts only lowercase 40-character source commits", () => {
		expect(
			validateSourceCommit("65a9afb1cece384a243c427be3d48b7d2461d169"),
		).toBe("65a9afb1cece384a243c427be3d48b7d2461d169");
		expect(() => validateSourceCommit("65a9afb")).toThrow();
		expect(() =>
			validateSourceCommit("65A9AFB1CECE384A243C427BE3D48B7D2461D169"),
		).toThrow();
	});

	test("refuses tracked and untracked source changes", () => {
		expect(() => assertCleanSource(" M apps/morphir-web/src/main.ts\n")).toThrow(
			/clean/i,
		);
		expect(() => assertCleanSource("?? scratch.txt\n")).toThrow(/clean/i);
		expect(() => assertCleanSource("")).not.toThrow();
	});

	test("produces the same sorted manifest for identical builds", async () => {
		const first = temporaryDirectory();
		const second = temporaryDirectory();
		for (const directory of [first, second]) {
			mkdirSync(path.join(directory, "assets"));
			writeFileSync(path.join(directory, "index.html"), "<main>Morphir</main>\n");
			writeFileSync(path.join(directory, "assets", "app-b.js"), "b\n");
			writeFileSync(path.join(directory, "assets", "app-a.css"), "a\n");
		}

		const one = await collectWebAssets(first);
		const two = await collectWebAssets(second);

		expect(one).toEqual(two);
		expect(one.assets.map(({ relativePath }) => relativePath)).toEqual([
			"assets/app-a.css",
			"assets/app-b.js",
			"index.html",
		]);
		expect(one.manifestSha256).toMatch(/^[0-9a-f]{64}$/);
	});

	test("rejects source maps and symbolic links", async () => {
		const sourceMap = temporaryDirectory();
		writeFileSync(path.join(sourceMap, "app.js.map"), "{}");
		await expect(collectWebAssets(sourceMap)).rejects.toThrow(/source map/i);

		const symbolicLink = temporaryDirectory();
		writeFileSync(path.join(symbolicLink, "target.js"), "safe");
		symlinkSync("target.js", path.join(symbolicLink, "alias.js"));
		await expect(collectWebAssets(symbolicLink)).rejects.toThrow(/symbolic link/i);
	});

	test("atomically stages assets and records provenance", async () => {
		const root = temporaryDirectory();
		const build = path.join(root, "dist");
		const destination = path.join(root, "assets");
		mkdirSync(build);
		mkdirSync(destination);
		writeFileSync(path.join(build, "index.html"), "new");
		writeFileSync(path.join(destination, "index.html"), "old");

		const manifest = await collectWebAssets(build);
		await replaceVendoredAssets({
			buildDirectory: build,
			destinationDirectory: destination,
			manifest,
			provenance: {
				webVersion: "0.1.0",
				uiSourceCommit: "65a9afb1cece384a243c427be3d48b7d2461d169",
				assetManifestSha256: manifest.manifestSha256,
			},
		});

		expect(readFileSync(path.join(destination, "index.html"), "utf8")).toBe(
			"new",
		);
		expect(
			JSON.parse(
				readFileSync(path.join(destination, "provenance.json"), "utf8"),
			),
		).toEqual({
			webVersion: "0.1.0",
			uiSourceCommit: "65a9afb1cece384a243c427be3d48b7d2461d169",
			assetManifestSha256: manifest.manifestSha256,
		});
		expect(
			readFileSync(path.join(destination, "embedded.rs"), "utf8"),
		).toContain('include_bytes!("index.html")');
		expect(
			readFileSync(path.join(destination, "embedded.rs"), "utf8"),
		).not.toContain("provenance.json");
	});
});
