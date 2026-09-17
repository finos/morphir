// Regenerates a canonical-YAML acceptance fixture for
// crates/morphir/tests/migrate_acceptance.rs from a v4 JSON file, using the
// TypeScript binding's reference writer as the oracle for the v4 YAML
// profile's canonical style (docs/spec/ir/schemas/v4/yaml-profile.md).
//
// This is the committed form of the one-off script described in
// .superpowers/sdd/2026-09-17-rust-mirror-stage-2-yaml-profile/task-6-report.md:
// it parses the input with the reference binding's JSON reader and writes it
// back with the reference binding's YAML writer (`writeYaml(parseJson(text))`),
// so the fixture pins the writer's style rather than a full semantic round
// trip through the reference binding's own v4 model.
//
// Usage (from the parent repository root):
//
//   bun run tools/gen-yaml-acceptance-fixture.ts <in.json> <out.yaml>
//
// The imports below resolve straight into the ecosystem/morphir-typescript
// submodule's TypeScript sources. Every module on the import path
// (packages/ir/src/codec/{json,yaml}/*.ts and packages/ir/src/model/*.ts)
// uses only relative imports and Bun/TypeScript built-ins, so this runs with
// no `bun install` in the submodule. If a future edit to those files adds a
// package dependency, run `bun install --cwd ecosystem/morphir-typescript`
// first.
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseJson } from "../ecosystem/morphir-typescript/packages/ir/src/codec/json/value.ts";
import { writeYaml } from "../ecosystem/morphir-typescript/packages/ir/src/codec/yaml/index.ts";

const toolsRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(toolsRoot);

function usage(): never {
	console.error(
		"usage: bun run tools/gen-yaml-acceptance-fixture.ts <in.json> <out.yaml>",
	);
	process.exit(2);
}

const [inputArg, outputArg] = process.argv.slice(2);
if (!inputArg || !outputArg) usage();

const inputPath = path.resolve(repositoryRoot, inputArg);
const outputPath = path.resolve(repositoryRoot, outputArg);

const inputText = readFileSync(inputPath, "utf8");
const parsed = parseJson(inputText);
if (!parsed.ok) {
	console.error(
		`error: ${path.relative(repositoryRoot, inputPath)} did not parse as JSON: ${JSON.stringify(parsed.error)}`,
	);
	process.exit(1);
}

const yaml = writeYaml(parsed.value);
writeFileSync(outputPath, yaml);
console.log(`wrote ${path.relative(repositoryRoot, outputPath)}`);
