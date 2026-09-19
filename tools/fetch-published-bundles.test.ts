import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	archiveUrl,
	assetUrls,
	parseExecutablePins,
	parsePins,
	pinnedVersion,
	verifyGuest,
} from "./fetch-published-bundles";

const root = join(import.meta.dir, "..");
const pinsText = readFileSync(join(root, ".config/published-extension-bundles.toml"), "utf8");

describe("published extension bundle pins", () => {
	test("every pin names a release tag, its artifact and the guest digest", () => {
		const pins = parsePins(pinsText);
		expect(Object.keys(pins).sort()).toEqual(["avro", "openapi", "python", "rust"]);
		for (const [shortId, pin] of Object.entries(pins)) {
			expect(pin.tag).toMatch(new RegExp(`^extension/${shortId}/v\\d+\\.\\d+\\.\\d+$`));
			const version = pin.tag.split("/v")[1];
			expect(pin.artifact.endsWith(`-${version}`)).toBe(true);
			expect(pin.sha256).toMatch(/^[0-9a-f]{64}$/);
		}
	});

	test("a pin without a digest is refused", () => {
		expect(() => parsePins('[bundles.avro]\ntag = "extension/avro/v0.1.1"\nartifact = "a-0.1.1"\n')).toThrow(
			/sha256/,
		);
	});

	test("the assets are the guest, its checksum file and the descriptor", () => {
		const base = "https://github.com/finos/morphir-rust/releases/download/extension/avro/v0.1.1/";
		expect(assetUrls("extension/avro/v0.1.1", "morphir-avro-extension-0.1.1")).toEqual({
			guest: `${base}morphir-avro-extension-0.1.1.wasm`,
			checksum: `${base}morphir-avro-extension-0.1.1.wasm.sha256`,
			descriptor: `${base}morphir-avro-extension-0.1.1.release.json`,
		});
	});

	test("a guest is checked against the digest pinned in this repository", () => {
		const guest = Buffer.from("guest");
		const digest = createHash("sha256").update(guest).digest("hex");
		expect(() => verifyGuest("avro", guest, digest)).not.toThrow();
		// A release asset that was replaced, together with its .sha256 file, still fails.
		expect(() => verifyGuest("avro", Buffer.from("replaced"), digest)).toThrow(/avro.*does not match the pinned sha256/);
	});

	test("an executable pin names its repository, tag, archive, digest and executable", () => {
		const pins = parseExecutablePins(pinsText);
		expect(Object.keys(pins).sort()).toEqual(["elm", "scala-elm"]);
		const elm = pins.elm;
		if (elm === undefined) {
			throw new Error("the pin file has no [executables.elm] entry");
		}
		expect(elm.repository).toBe("finos/morphir-elm");
		expect(elm.tag).toMatch(/^extension\/elm\/v\d+\.\d+\.\d+$/);
		// CI runs on x86_64 Linux, so that is the archive it pins.
		expect(elm.archive).toBe(`morphir-elm-extension-${elm.tag.split("/v")[1]}-x86_64-unknown-linux-gnu.tgz`);
		expect(elm.executable).toBe("morphir-elm-extension");
		expect(elm.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	test("an executable pin without a repository or a digest is refused", () => {
		const pin = 'tag = "extension/elm/v0.1.0"\narchive = "a.tgz"\nexecutable = "a"\n';
		expect(() => parseExecutablePins(`[executables.elm]\n${pin}sha256 = "${"0".repeat(64)}"\n`)).toThrow(
			/repository/,
		);
		expect(() => parseExecutablePins(`[executables.elm]\nrepository = "finos/morphir-elm"\n${pin}`)).toThrow(
			/sha256/,
		);
	});

	test("a pin of a raw executable names an asset and no archive", () => {
		// finos/morphir-scala releases morphir-scala-elm as the executable itself, with its v* release.
		const scala = parseExecutablePins(pinsText)["scala-elm"];
		if (scala === undefined) {
			throw new Error("the pin file has no [executables.scala-elm] entry");
		}
		expect(scala.repository).toBe("finos/morphir-scala");
		expect(scala.tag).toMatch(/^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/);
		expect(scala.asset).toBe(`morphir-scala-elm-linux-amd64-${pinnedVersion(scala.tag)}`);
		expect(scala.archive).toBeUndefined();
		expect(scala.executable).toBe("morphir-scala-elm");
		expect(scala.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	test("an executable pin names exactly one of archive and asset", () => {
		const head = '[executables.x]\nrepository = "o/r"\ntag = "v1.0.0"\nexecutable = "x"\n';
		const digest = `sha256 = "${"0".repeat(64)}"\n`;
		expect(() => parseExecutablePins(head + digest)).toThrow(/archive or asset/);
		expect(() => parseExecutablePins(`${head}${digest}archive = "a.tgz"\nasset = "a"\n`)).toThrow(
			/archive or asset/,
		);
	});

	test("a root release tag carries its version too", () => {
		expect(pinnedVersion("v0.5.0-M06")).toBe("0.5.0-M06");
	});

	test("the version of a pin is the version in its tag", () => {
		// The CLI refuses an extension whose reported version differs from the version it was
		// installed with, so the install test needs the version of the pinned release.
		expect(pinnedVersion("extension/elm/v0.1.0")).toBe("0.1.0");
		expect(pinnedVersion("extension/elm/v1.2.3-rc.1")).toBe("1.2.3-rc.1");
		expect(() => pinnedVersion("extension/elm/latest")).toThrow(/version/);
	});

	test("an archive is fetched from the repository the pin names", () => {
		expect(archiveUrl({ repository: "finos/morphir-elm", tag: "extension/elm/v0.1.0", archive: "a.tgz" })).toBe(
			"https://github.com/finos/morphir-elm/releases/download/extension/elm/v0.1.0/a.tgz",
		);
	});
});
