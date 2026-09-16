// Fails when a corpus under docs/spec/ir/fixtures and its vendored copy differ.
// Usage: bun run tools/check-vendored-fixture.ts <source> <copy>
import { readFileSync } from "node:fs";

const [source, copy] = process.argv.slice(2);
if (!source || !copy) {
	console.error("usage: check-vendored-fixture <source> <copy>");
	process.exit(2);
}
const a = readFileSync(source);
const b = readFileSync(copy);
if (!a.equals(b)) {
	console.error(`${copy} differs from ${source}; copy the source over it byte for byte`);
	process.exit(1);
}
console.log(`${copy} matches ${source}`);
