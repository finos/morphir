// Downloads the published extension bundles pinned in .config/published-extension-bundles.toml.
// Usage: bun run tools/fetch-published-bundles.ts [output-directory]
//
// CI runs the CLI built from a pull request against these bundles, which are the ones users
// install. Each guest is checked against the sha256 pinned in this repository, not against the
// .sha256 asset of the same release, so replaced release assets fail instead of running.
// Each bundle directory holds exactly what `extension repository publish` expects: the
// descriptor named release.json, the guest and its checksum file. A process extension is pinned
// under [executables.<id>] and unpacked to one executable.
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

// A process extension is one executable per platform, released as an archive by the repository
// that owns it. CI pins the archive for the platform it runs on.
export type ExecutablePin = { repository: string; tag: string; archive: string; sha256: string; executable: string };

export function parseExecutablePins(text: string): Record<string, ExecutablePin> {
	const executables =
		(Bun.TOML.parse(text) as { executables?: Record<string, Partial<ExecutablePin>> }).executables ?? {};
	const pins: Record<string, ExecutablePin> = {};
	for (const [shortId, pin] of Object.entries(executables)) {
		for (const key of ["repository", "tag", "archive", "sha256", "executable"] as const) {
			if (typeof pin[key] !== "string" || pin[key] === "") {
				throw new Error(`executables.${shortId} has no ${key}`);
			}
		}
		pins[shortId] = pin as ExecutablePin;
	}
	return pins;
}

/** The version a release tag such as extension/elm/v0.1.0 names. */
export function pinnedVersion(tag: string): string {
	const match = /\/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$/.exec(tag);
	if (match?.[1] === undefined) {
		throw new Error(`'${tag}' does not end with a version`);
	}
	return match[1];
}

export function archiveUrl(pin: Pick<ExecutablePin, "repository" | "tag" | "archive">): string {
	return `https://github.com/${pin.repository}/releases/download/${pin.tag}/${pin.archive}`;
}

export function assetUrls(tag: string, artifact: string) {
	const base = `${RELEASES}/${tag}/${artifact}`;
	return { guest: `${base}.wasm`, checksum: `${base}.wasm.sha256`, descriptor: `${base}.release.json` };
}

export function verifyGuest(shortId: string, guest: Uint8Array, sha256: string): void {
	const actual = createHash("sha256").update(guest).digest("hex");
	if (actual !== sha256.toLowerCase()) {
		throw new Error(`${shortId}: the download (${actual}) does not match the pinned sha256 (${sha256})`);
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

async function fetchExecutable(shortId: string, pin: ExecutablePin, output: string): Promise<void> {
	const archive = await download(archiveUrl(pin));
	verifyGuest(shortId, archive, pin.sha256);
	const directory = join(output, shortId);
	rmSync(directory, { recursive: true, force: true });
	mkdirSync(directory, { recursive: true });
	const archivePath = join(directory, pin.archive);
	writeFileSync(archivePath, archive);
	const unpack = Bun.spawnSync(["tar", "-xzf", archivePath, "-C", directory]);
	if (unpack.exitCode !== 0) {
		throw new Error(`${shortId}: cannot unpack ${pin.archive}: ${unpack.stderr.toString()}`);
	}
	rmSync(archivePath);
	const executable = join(directory, pin.executable);
	if (!existsSync(executable)) {
		throw new Error(`${shortId}: ${pin.archive} does not hold ${pin.executable}`);
	}
	chmodSync(executable, 0o755);
	// The install test gives the CLI this version; the extension must report the same one.
	writeFileSync(join(directory, "version.txt"), `${pinnedVersion(pin.tag)}\n`);
	console.log(`${shortId}: ${pin.tag} -> ${executable}`);
}

if (import.meta.main) {
	const root = join(import.meta.dir, "..");
	const output = resolve(process.argv[2] ?? join(root, ".dev/out/published-bundles"));
	const pinsFile = readFileSync(join(root, ".config/published-extension-bundles.toml"), "utf8");
	const pins = parsePins(pinsFile);
	for (const [shortId, pin] of Object.entries(pins)) {
		await fetchBundle(shortId, pin, output);
	}
	for (const [shortId, pin] of Object.entries(parseExecutablePins(pinsFile))) {
		await fetchExecutable(shortId, pin, output);
	}
}
