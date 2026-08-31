// Publishes the beads export to the dedicated sync branch.
//
//   bun run publish-beads.ts [--push] [--dry-run]
//
// The Dolt database is authoritative and syncs over refs/dolt/data. The JSONL
// export is a readable mirror, and it used to be committed to main, where it
// produced churn on every issue change and drifted from the database in both
// directions (morphir-5uau). It now lives on its own branch instead.
//
// The branch is written with git plumbing rather than by checking it out, so
// publishing never disturbs the working tree and works the same from a linked
// worktree. It holds only the issue export, shares no history with main, and is
// not meant to be merged.
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const BRANCH = "beads-sync";
const EXPORT_PATH = ".beads/issues.jsonl";
const INTERACTIONS_PATH = ".beads/interactions.jsonl";

const push = process.argv.includes("--push");
const dryRun = process.argv.includes("--dry-run");

function git(args: string[], options: { env?: Record<string, string> } = {}) {
	const result = Bun.spawnSync(["git", ...args], {
		cwd: repositoryRoot,
		env: { ...process.env, ...options.env },
		stderr: "pipe",
	});
	if (result.exitCode !== 0) {
		console.error(`error: git ${args.join(" ")}`);
		console.error(result.stderr.toString().trim());
		process.exit(1);
	}
	return result.stdout.toString().trim();
}

// Returns null rather than exiting, for refs that legitimately may not exist.
function resolve(ref: string): string | null {
	const result = Bun.spawnSync(["git", "rev-parse", "--verify", "-q", ref], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});
	return result.exitCode === 0 ? result.stdout.toString().trim() : null;
}

function isAncestor(maybeAncestor: string, descendant: string): boolean {
	const result = Bun.spawnSync(
		["git", "merge-base", "--is-ancestor", maybeAncestor, descendant],
		{ cwd: repositoryRoot, stderr: "pipe" },
	);
	return result.exitCode === 0;
}

// The published branch may exist only as a remote-tracking ref, in a fresh clone
// that never checked it out, or the local ref may be behind after someone else
// published. Parenting on a local-only lookup would build an unrelated root
// commit whose push is rejected as non-fast-forward.
function resolveParent(): string | null {
	// Best effort: a publish should still work offline.
	Bun.spawnSync(["git", "fetch", "--quiet", "origin", BRANCH], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});

	const local = resolve(`refs/heads/${BRANCH}`);
	const remote = resolve(`refs/remotes/origin/${BRANCH}`);

	if (local === null) return remote;
	if (remote === null) return local;
	if (local === remote) return local;
	if (isAncestor(local, remote)) return remote;
	if (isAncestor(remote, local)) return local;

	console.error(
		`error: ${BRANCH} and origin/${BRANCH} have diverged, so publishing would`,
	);
	console.error("discard one of them. Reconcile them first:");
	console.error(`    git log --oneline ${BRANCH} origin/${BRANCH}`);
	console.error(
		`    git update-ref refs/heads/${BRANCH} origin/${BRANCH}   # keep the remote`,
	);
	process.exit(1);
}

// Export straight from the database, so what gets published is never a stale
// working copy someone edited by hand.
const exported = Bun.spawnSync(["bd", "export"], {
	cwd: repositoryRoot,
	stderr: "pipe",
});
if (exported.exitCode !== 0) {
	console.error("error: could not read the beads database");
	console.error(exported.stderr.toString().trim());
	process.exit(1);
}

const scratch = mkdtempSync(path.join(tmpdir(), "beads-publish-"));
try {
	const issuesFile = path.join(scratch, "issues.jsonl");
	writeFileSync(issuesFile, exported.stdout);
	const issuesBlob = git(["hash-object", "-w", "--path", EXPORT_PATH, issuesFile]);

	const entries: Array<[string, string]> = [[EXPORT_PATH, issuesBlob]];

	const parentCommit = resolveParent();

	// Build the tree in a scratch index so the real one is untouched. Seeding it
	// from the parent means anything this machine has no local copy of carries
	// forward instead of being dropped from the branch: a fresh clone has no
	// interaction log, and rebuilding the tree from scratch would silently delete
	// the published one.
	const indexFile = path.join(scratch, "index");
	const env = { GIT_INDEX_FILE: indexFile };
	if (parentCommit) {
		git(["read-tree", parentCommit], { env });
		// Earlier publications carried bd's interaction log. bd rotates that file,
		// dropping older records as it appends newer ones, so republishing it made
		// the branch tip appear to lose audit history. It is derived from the
		// database and is not issue data, so the branch no longer carries it.
		git(["update-index", "--force-remove", INTERACTIONS_PATH], { env });
	}
	for (const [file, blob] of entries) {
		git(["update-index", "--add", "--cacheinfo", `100644,${blob},${file}`], { env });
	}
	const tree = git(["write-tree"], { env });

	if (parentCommit) {
		const parentTree = git(["rev-parse", `${parentCommit}^{tree}`]);
		if (parentTree === tree) {
			console.log(`${BRANCH} is already up to date (${parentCommit.slice(0, 8)})`);
			process.exit(0);
		}
	}

	const issueCount = exported.stdout.toString().split("\n").filter((l) => l.trim() !== "").length;
	const message = `chore(beads): publish ${issueCount} issues`;

	if (dryRun) {
		console.log(`would commit tree ${tree.slice(0, 8)} to ${BRANCH}`);
		console.log(`  parent:  ${parentCommit ? parentCommit.slice(0, 8) : "(new branch)"}`);
		console.log(`  message: ${message}`);
		for (const [file] of entries) console.log(`  ${file}`);
		process.exit(0);
	}

	const commit = git([
		"commit-tree",
		tree,
		...(parentCommit ? ["-p", parentCommit] : []),
		"-m",
		message,
	]);
	git(["update-ref", `refs/heads/${BRANCH}`, commit]);
	console.log(`${BRANCH} updated to ${commit.slice(0, 8)}: ${message}`);

	if (push) {
		git(["push", "origin", `refs/heads/${BRANCH}:refs/heads/${BRANCH}`]);
		console.log(`pushed ${BRANCH} to origin`);
	} else {
		console.log(`  push it with: git push origin ${BRANCH}`);
	}
} finally {
	rmSync(scratch, { recursive: true, force: true });
}
