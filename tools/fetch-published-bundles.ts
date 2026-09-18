// Downloads the published extension bundles pinned in .config/published-extension-bundles.toml.
// Usage: bun run tools/fetch-published-bundles.ts [output-directory]
//
// CI runs the CLI built from a pull request against these bundles, which are the ones users
// install. Each guest is checked against the sha256 pinned in this repository, not against the
// .sha256 asset of the same release, so replaced release assets fail instead of running.
// Each bundle directory holds exactly what `extension repository publish` expects: the
// descriptor named release.json, the guest and its checksum file.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const RELEASES = "https://github.com/finos/morphir-rust/releases/download";

export type Pin = { tag: string; artifact: string; sha256: string };

export function parsePins(text: string): Record<string, Pin> {
	const bundles = (Bun.TOML.parse(text) as { bundles?: Record<string, Partial<Pin>> }).bundles ?? {};
	const pins: Record<string, Pin> = {};
	for (const [shortId, pin] of Object.entries(bundles)) {
		for (const key of ["tag", "artifact", "sha256"] as const) {
			if (typeof pin[key] !== "string" || pin[key] === "") {
				throw new Error(`bundles.${shortId} has no ${key}`);
			}
		}
		pins[shortId] = pin as Pin;
	}
	return pins;
}

export function assetUrls(tag: string, artifact: string) {
	const base = `${RELEASES}/${tag}/${artifact}`;
	return { guest: `${base}.wasm`, checksum: `${base}.wasm.sha256`, descriptor: `${base}.release.json` };
}

export function verifyGuest(shortId: string, guest: Uint8Array, sha256: string): void {
	const actual = createHash("sha256").update(guest).digest("hex");
	if (actual !== sha256.toLowerCase()) {
		throw new Error(`${shortId}: the downloaded guest (${actual}) does not match the pinned sha256 (${sha256})`);
	}
}

async function download(url: string): Promise<Uint8Array> {
	const response = await fetch(url);
	if (!response.ok) {
		throw new Error(`${url}: HTTP ${response.status}`);
	}
	return new Uint8Array(await response.arrayBuffer());
}

async function fetchBundle(shortId: string, pin: Pin, output: string): Promise<void> {
	const urls = assetUrls(pin.tag, pin.artifact);
	const guest = await download(urls.guest);
	verifyGuest(shortId, guest, pin.sha256);
	const bundle = join(output, shortId);
	rmSync(bundle, { recursive: true, force: true });
	mkdirSync(bundle, { recursive: true });
	writeFileSync(join(bundle, `${pin.artifact}.wasm`), guest);
	writeFileSync(join(bundle, `${pin.artifact}.wasm.sha256`), await download(urls.checksum));
	writeFileSync(join(bundle, "release.json"), await download(urls.descriptor));
	console.log(`${shortId}: ${pin.tag} -> ${bundle}`);
}

if (import.meta.main) {
	const root = join(import.meta.dir, "..");
	const output = resolve(process.argv[2] ?? join(root, ".dev/out/published-bundles"));
	const pins = parsePins(readFileSync(join(root, ".config/published-extension-bundles.toml"), "utf8"));
	for (const [shortId, pin] of Object.entries(pins)) {
		await fetchBundle(shortId, pin, output);
	}
}
