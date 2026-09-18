import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assetUrls, parsePins, verifyGuest } from "./fetch-published-bundles";

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
});
