// Regenerates the canonical acceptance fixtures for
// crates/morphir/tests/migrate_acceptance.rs from a v4 JSON file, using the
// TypeScript binding's reference writers as the oracle: the single-file YAML
// profile's canonical style (docs/spec/ir/schemas/v4/yaml-profile.md), and the
// document-tree layout (docs/spec/ir/schemas/v4/document-tree-files.md).
//
// This is the committed form of the one-off script described in
// .superpowers/sdd/2026-09-17-rust-mirror-stage-2-yaml-profile/task-6-report.md:
// it parses the input with the reference binding's JSON reader and writes it
// back with the reference binding's YAML writer (`writeYaml(parseJson(text))`),
// so the fixture pins the writer's style rather than a full semantic round
// trip through the reference binding's own v4 model. The `--tree` mode reads
// the same input through the binding's own v4 model instead — a tree is a
// shape, not a restyling, so `writeTree` needs the model, not the value tree —
// and lays the result out with the Node adapter, one physical file per logical
// path.
//
// This script does NOT import from the ecosystem/morphir-typescript
// submodule directly: `tools/tsconfig.json` includes every `*.ts` under
// `tools/`, and in CI the submodule is checked out without its own
// dependencies installed (e.g. the `yaml` package that
// packages/ir/src/codec/yaml/index.ts needs). A direct import would make
// `bun run --cwd tools typecheck` resolve into unbuilt/uninstalled submodule
// sources and fail. Instead, this script shells out: it resolves the
// submodule root, installs its dependencies on demand, writes a small
// runner script into the submodule's gitignored `.dev/` directory (so it
// never touches submodule-tracked files), and runs that script with Bun,
// with the submodule as its working directory. The runner script's own
// imports are internal to the submodule, so the submodule's own
// `tsconfig.json`/type-checking never sees this file, and this file never
// imports submodule sources, so `tools/tsconfig.json` never sees them
// either.
//
// Usage (from the parent repository root):
//
//   bun run tools/gen-yaml-acceptance-fixture.ts <in.json> <out.yaml>
//   bun run tools/gen-yaml-acceptance-fixture.ts --tree <in.json> <out-dir>
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(toolsRoot);
const submoduleRoot = path.join(
	repositoryRoot,
	"ecosystem",
	"morphir-typescript",
);

// The longest physical path a tree may hold, counted from the distribution
// root. The figure is the transport's default on both sides
// (`morphir_common::ir_transport::DEFAULT_PATH_BUDGET`), and the distribution
// manifest records it, so the fixture only matches the CLI when the two agree.
const PATH_BUDGET = 4000;

function usage(): never {
	console.error(
		"usage: bun run tools/gen-yaml-acceptance-fixture.ts <in.json> <out.yaml>\n" +
			"       bun run tools/gen-yaml-acceptance-fixture.ts --tree <in.json> <out-dir>",
	);
	process.exit(2);
}

const args = process.argv.slice(2);
const tree = args[0] === "--tree";
const [inputArg, outputArg] = tree ? args.slice(1) : args;
if (!inputArg || !outputArg) usage();

const inputPath = path.resolve(repositoryRoot, inputArg);
const outputPath = path.resolve(repositoryRoot, outputArg);

if (!existsSync(inputPath)) {
	console.error(
		`error: input file not found: ${path.relative(repositoryRoot, inputPath)}`,
	);
	process.exit(1);
}

// The reference writer's dependencies (e.g. the `yaml` package used by
// packages/ir/src/codec/yaml/index.ts) live in the submodule's own
// node_modules, not the parent repository's. Install them on demand rather
// than unconditionally, so a fixture regeneration in an already-set-up
// checkout doesn't re-run `bun install` every time.
const submoduleNodeModules = path.join(submoduleRoot, "node_modules");
if (!existsSync(submoduleNodeModules)) {
	console.log(
		`installing dependencies in ${path.relative(repositoryRoot, submoduleRoot)}...`,
	);
	const install = Bun.spawnSync({
		cmd: ["bun", "install", "--frozen-lockfile"],
		cwd: submoduleRoot,
		stdio: ["inherit", "inherit", "inherit"],
		windowsHide: true,
	});
	if (install.exitCode !== 0) {
		console.error(
			`error: bun install --frozen-lockfile failed in ${path.relative(repositoryRoot, submoduleRoot)}`,
		);
		process.exit(install.exitCode ?? 1);
	}
}

// `writeTreeToDirectory` removes nothing already under its destination, so a
// file the writer no longer produces would survive a regeneration and only
// show up as a spurious acceptance failure later. Start from an empty
// directory instead.
if (tree) {
	rmSync(outputPath, { recursive: true, force: true });
	mkdirSync(outputPath, { recursive: true });
}

// Run the reference writer inside the submodule instead of importing its
// sources into this file: a small runner script, written under the
// submodule's gitignored .dev/ directory, does the actual writing with the
// submodule as its own working directory, so its imports resolve against the
// submodule's installed dependencies and its own tsconfig, not the parent's.
const runnerDir = path.join(submoduleRoot, ".dev");
mkdirSync(runnerDir, { recursive: true });
const runnerPath = path.join(
	runnerDir,
	tree
		? "gen-tree-acceptance-fixture-runner.ts"
		: "gen-yaml-acceptance-fixture-runner.ts",
);
const header = `// Generated by tools/gen-yaml-acceptance-fixture.ts. Do not edit by hand;
// this file lives under the gitignored .dev/ directory and is safe to
// delete or regenerate at any time.
`;
const singleFileRunner = `${header}import { readFileSync, writeFileSync } from "node:fs";
import { parseJson } from "../packages/ir/src/codec/json/value.ts";
import { writeYaml } from "../packages/ir/src/codec/yaml/index.ts";

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
	console.error(
		"usage: bun run gen-yaml-acceptance-fixture-runner.ts <in.json> <out.yaml>",
	);
	process.exit(2);
}

const inputText = readFileSync(inputPath, "utf8");
const parsed = parseJson(inputText);
if (!parsed.ok) {
	console.error(
		\`error: \${inputPath} did not parse as JSON: \${JSON.stringify(parsed.error)}\`,
	);
	process.exit(1);
}

const yaml = writeYaml(parsed.value);
writeFileSync(outputPath, yaml);
`;
const treeRunner = `${header}import { readFileSync } from "node:fs";
import { YAML_PROFILE } from "../packages/ir/src/codec/yaml/index.ts";
import { writeTreeToDirectory } from "../packages/ir/src/layout/node.ts";
import { writeTree } from "../packages/ir/src/layout/write-tree.ts";
import { json } from "../packages/ir/src/versions/v4/index.ts";

const [inputPath, outputPath, budgetText] = process.argv.slice(2);
if (!inputPath || !outputPath || !budgetText) {
	console.error(
		"usage: bun run gen-tree-acceptance-fixture-runner.ts <in.json> <out-dir> <path-budget>",
	);
	process.exit(2);
}

const file = json.read(readFileSync(inputPath, "utf8"));
if (!file.ok) {
	console.error(
		\`error: \${inputPath} did not read as v4 IR: \${JSON.stringify(file.error)}\`,
	);
	process.exit(1);
}

const tree = writeTree(file.value, {
	profile: YAML_PROFILE,
	pathBudget: Number(budgetText),
});
if (!tree.ok) {
	console.error(
		\`error: \${inputPath} has no document tree: \${JSON.stringify(tree.error)}\`,
	);
	process.exit(1);
}

await writeTreeToDirectory(outputPath, tree.value, YAML_PROFILE);
console.log(\`wrote \${tree.value.size} files\`);
`;
writeFileSync(runnerPath, tree ? treeRunner : singleFileRunner);

const run = Bun.spawnSync({
	cmd: tree
		? ["bun", "run", runnerPath, inputPath, outputPath, String(PATH_BUDGET)]
		: ["bun", "run", runnerPath, inputPath, outputPath],
	cwd: submoduleRoot,
	stdio: ["inherit", "inherit", "inherit"],
	windowsHide: true,
});
if (run.exitCode !== 0) {
	console.error("error: the reference writer failed; see output above");
	process.exit(run.exitCode ?? 1);
}

console.log(`wrote ${path.relative(repositoryRoot, outputPath)}`);
