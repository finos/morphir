// Migration source parity only. `morphir mck schema check` owns validation.
// Keep this byte comparison until IR-4 changes contract source ownership.
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function contractDrift(repositoryRoot: string): string[] {
	const originals = path.join(repositoryRoot, "ecosystem/morphir-typescript/packages/mck");
	const schema = path.join(originals, "protocol.schema.json");
	if (!existsSync(schema)) {
		console.log(`contract copies: skipped (${path.relative(repositoryRoot, schema)} not checked out)`);
		return [];
	}
	return ["protocol.schema.json", "protocol.example.json"].flatMap((name) => {
		const here = path.join(repositoryRoot, "spec/ir/mck", name);
		const there = path.join(originals, name);
		if (!existsSync(there)) return [`${name}: the submodule original is missing`];
		if (!readFileSync(here).equals(readFileSync(there))) {
			return [`${name}: differs from ${path.relative(repositoryRoot, there)}; re-copy it`];
		}
		console.log(`contract copy ${name}: ok (identical to the submodule)`);
		return [];
	});
}

if (import.meta.main) {
	const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
	const failures = contractDrift(root);
	for (const failure of failures) console.error(`FAIL ${failure}`);
	if (failures.length > 0) process.exitCode = 1;
}
