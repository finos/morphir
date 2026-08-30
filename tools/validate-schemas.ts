// Validates every JSON Schema source under website/static/schemas/ against the
// JSON Schema metaschema.
//
//   bun run validate-schemas.ts
//
// The glob is expanded here rather than by the shell. mise runs tasks through
// the platform shell, and the default Windows shell does not expand "*.yaml", so
// jsonschema received the literal pattern and failed. Bash is not a portable
// fallback either: a Windows box may have only the WSL launcher on PATH.
import { Glob } from "bun";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const schemaDir = path.join(repositoryRoot, "website", "static", "schemas");

const glob = new Glob("*.yaml");
const files = (await Array.fromAsync(glob.scan({ cwd: schemaDir })))
	.sort()
	.map((name) => path.join(schemaDir, name));

if (files.length === 0) {
	console.error(`error: no .yaml schemas found in ${schemaDir}`);
	process.exit(1);
}

const result = Bun.spawnSync(["jsonschema", "metaschema", ...files], {
	cwd: repositoryRoot,
	stdout: "inherit",
	stderr: "inherit",
});

if (result.exitCode !== 0) {
	process.exit(result.exitCode ?? 1);
}

console.log(`${files.length} schema(s) valid against the metaschema`);
