// Points git at the repository's .husky directory so the checked-in hooks run.
//
//   bun run install-git-hooks.ts [--check]
//
// The hooks in .husky were dormant in every clone (morphir-4ohq): package.json
// declares "prepare": "husky", but that only fires on an npm install, and this
// repository is built with cargo, bun and mise, so nobody had a reason to run
// one. core.hooksPath stayed unset and .git/hooks held nothing but samples, which
// meant the commit-msg guard that strips AI co-author trailers for EasyCLA had
// never run.
//
// Setting core.hooksPath directly makes activation independent of node. It stays
// compatible with husky: v9 sets the same key, so a later npm install is not
// undone by this and does not undo it.
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const hooksPath = ".husky";
const check = process.argv.includes("--check");

function git(...args: string[]): { code: number; out: string } {
	const result = Bun.spawnSync(["git", ...args], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});
	return {
		code: result.exitCode ?? 1,
		out: result.stdout.toString().trim(),
	};
}

const current = git("config", "--get", "core.hooksPath").out;

// git resolves core.hooksPath from the working directory, so a relative path
// works in the main checkout and in every linked worktree.
if (current === hooksPath) {
	console.log(`git hooks already active: core.hooksPath = ${hooksPath}`);
	process.exit(0);
}

if (check) {
	console.error(
		current === ""
			? "error: git hooks are not active (core.hooksPath is unset)."
			: `error: core.hooksPath is ${current}, expected ${hooksPath}.`,
	);
	console.error("Run: mise run hooks:install");
	process.exit(1);
}

if (current !== "") {
	console.log(`replacing core.hooksPath ${current} with ${hooksPath}`);
}

const set = git("config", "core.hooksPath", hooksPath);
if (set.code !== 0) {
	console.error("error: could not set core.hooksPath");
	process.exit(1);
}

console.log(`git hooks active: core.hooksPath = ${hooksPath}`);
console.log("  commit-msg  strips AI co-author trailers (EasyCLA compliance)");
console.log("  pre-commit  guards go.work, the .beads symlink, and beads drift");
console.log("  pre-push    checks formatting");
