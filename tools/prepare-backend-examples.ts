/** Stage pinned downloaded WASM bundles. Scenarios perform publication and installation. */
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parsePins, verifyGuest } from "./fetch-published-bundles.ts";

export function prepareBackendExamples(root: string, bundles: string): void {
	const pins = parsePins(readFileSync(join(root, ".config/published-extension-bundles.toml"), "utf8"));
	// Read and verify everything before replacing either example's prepared inputs.
	const prepared = ["avro", "openapi"].map(id => {
		const pin = pins[id];
		if (!pin) throw new Error(`No published bundle pin for ${id}.`);
		const guestName = `${pin.artifact}.wasm`;
		const guest = readFileSync(join(bundles, id, guestName));
		verifyGuest(id, guest, pin.sha256);
		return {
			id,
			files: [
				{ name: guestName, bytes: guest },
				{ name: `${guestName}.sha256`, bytes: readFileSync(join(bundles, id, `${guestName}.sha256`)) },
				{ name: "release.json", bytes: readFileSync(join(bundles, id, "release.json")) },
			],
		};
	});
	for (const { id, files } of prepared) {
		const destinations = [
			join(root, "examples/backends", id, ".itest/bundle"),
			join(root, "examples/backends/v4-published-rejection/.itest", id),
		];
		for (const destination of destinations) {
			rmSync(destination, { recursive: true, force: true });
			mkdirSync(destination, { recursive: true });
			for (const { name, bytes } of files) writeFileSync(join(destination, name), bytes);
		}
	}
}

if (import.meta.main) {
	const root = resolve(import.meta.dir, "..");
	const bundles = resolve(process.argv[2] ?? join(root, ".dev/out/published-bundles"));
	prepareBackendExamples(root, bundles);
	console.log("Prepared Avro and OpenAPI bundles. Run morphir itest examples --tag suite:wasm-backends.");
}
