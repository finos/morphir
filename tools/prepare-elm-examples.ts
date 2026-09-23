/** Stage an explicitly supplied Elm release for isolated CLI examples. No downloads or tests. */
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** The pinned reference release; see .config/published-extension-bundles.toml. */
export const REQUIRED_VERSION = "0.3.0";

export function prepareElmExamples(root: string, executable: string, version: string): void {
	if (version !== REQUIRED_VERSION) {
		throw new Error(`These examples require morphir-elm extension ${REQUIRED_VERSION}.`);
	}
	const bytes = readFileSync(executable);
	if (!bytes.length) throw new Error("Elm extension executable is empty.");
	const filename = process.platform === "win32" ? "morphir-elm.exe" : "morphir-elm";
	const source = `artifacts/${filename}`;
	const record = {
		schemaVersion: "1.0",
		id: "morphir-elm",
		name: "Morphir Elm frontend",
		version,
		channels: ["stable"],
		mepVersions: ["0.1"],
		// The published record names the capability kinds the executable reports, or the host
		// refuses the session. 0.3.0 serves workspace discovery for single-file compiles.
		capabilities: ["frontend", "workspace"],
		frontend: {
			languages: [{ id: "elm", fileExtensions: [".elm"] }],
			irVersions: ["3"],
			compile: true,
		},
		artifacts: [{
			runtime: "process",
			platform: {
				os: process.platform === "darwin" ? "macos" : process.platform === "win32" ? "windows" : process.platform,
				arch: process.arch === "arm64" ? "aarch64" : process.arch === "x64" ? "x86_64" : process.arch,
			},
			source: { kind: "local-file", path: source },
			sha256: createHash("sha256").update(bytes).digest("hex"),
			filename,
			args: [],
			executable: true,
		}],
	};
	for (const example of ["morphir-elm-compat", "elm/single-file-functions", "elm/classic-json"]) {
		const repository = join(root, "examples", example, ".itest/elm");
		mkdirSync(join(repository, "artifacts"), { recursive: true });
		mkdirSync(join(repository, "extensions"), { recursive: true });
		writeFileSync(join(repository, source), bytes);
		chmodSync(join(repository, source), 0o755);
		writeFileSync(join(repository, "extensions/morphir-elm.jsonl"), `${JSON.stringify(record)}\n`);
	}
}

if (import.meta.main) {
	const executable = process.argv[2] ?? process.env.MORPHIR_ELM_EXTENSION_BIN;
	if (!executable) {
		throw new Error("Pass the downloaded morphir-elm-extension executable, or set MORPHIR_ELM_EXTENSION_BIN.");
	}
	const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
	prepareElmExamples(root, executable, process.env.MORPHIR_ELM_EXTENSION_VERSION ?? REQUIRED_VERSION);
	console.log(`Prepared reference Elm examples with extension ${REQUIRED_VERSION}. Run morphir itest examples --tag suite:elm-reference.`);
}
