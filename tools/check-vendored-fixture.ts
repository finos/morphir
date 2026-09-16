// Fails when a corpus under docs/spec/ir/fixtures and its vendored copy differ.
// Usage: bun run tools/check-vendored-fixture.ts <source> <copy>
//
// The source is tracked in this repository, so its absence is always an error.
// The copy usually lives in a git submodule, and no CI job here checks out
// submodules, so an absent copy is reported and skipped the way
// gen-naming-corpus.ts skips its vendored write.
import { existsSync, readFileSync } from "node:fs";

const [source, copy] = process.argv.slice(2);
if (!source || !copy) {
	console.error("usage: check-vendored-fixture <source> <copy>");
	process.exit(2);
}
if (!existsSync(source)) {
	console.error(`error: ${source} does not exist`);
	process.exit(1);
}
if (!existsSync(copy)) {
	console.log(`${copy} is absent; skipping the vendored-copy check`);
	process.exit(0);
}
const a = readFileSync(source);
const b = readFileSync(copy);
if (!a.equals(b)) {
	console.error(`${copy} differs from ${source}; copy the source over it byte for byte`);
	process.exit(1);
}
console.log(`${copy} matches ${source}`);
