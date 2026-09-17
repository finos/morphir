// Runs the `jsonschema` CLI with its path globs expanded here rather than by
// the shell.
//
// mise runs a task's `run` lines through the platform's default shell, and the
// default Windows shell expands nothing: `website/static/schemas/*.yaml`
// reaches `jsonschema` verbatim and it reports the literal path as missing.
// The POSIX answers (`sh -c`, `find … | xargs`) are not portable either — a
// Windows box may carry only the WSL launcher, and `xargs` is not there at
// all. `.config/mise/tasks/examples/validate.py` already expands its own globs
// for the same reason; this is the same move for the tasks that call
// `jsonschema` directly.
//
// Every argument containing `*` is expanded, relative to the repository root,
// into its sorted matches; everything else is passed through untouched. On a
// platform whose shell does expand globs there is nothing left to expand by
// the time this runs, so the behaviour is the same on both.
//
// Usage (from the parent repository root):
//
//   bun run tools/jsonschema-glob.ts lint website/static/schemas/*.yaml --exclude enum_with_type
//
// Leave the glob unquoted in a mise task: a POSIX shell then expands it before
// this runs, and the Windows shell hands it over intact. Quoting it would make
// the quotes part of the argument on Windows.
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(toolsRoot);

const args = process.argv.slice(2);
if (args.length === 0) {
	console.error(
		"usage: bun run tools/jsonschema-glob.ts <jsonschema arguments...>",
	);
	process.exit(2);
}

const expanded: string[] = [];
for (const arg of args) {
	if (!arg.includes("*")) {
		expanded.push(arg);
		continue;
	}
	const matches = [
		...new Bun.Glob(arg).scanSync({ cwd: repositoryRoot, onlyFiles: true }),
	]
		.map((match) => match.replaceAll("\\", "/"))
		.sort();
	if (matches.length === 0) {
		console.error(`error: no file matches ${arg}`);
		process.exit(1);
	}
	expanded.push(...matches);
}

const run = Bun.spawnSync({
	cmd: ["jsonschema", ...expanded],
	cwd: repositoryRoot,
	stdio: ["inherit", "inherit", "inherit"],
	windowsHide: true,
});
process.exit(run.exitCode ?? 1);
