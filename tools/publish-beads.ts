// Publishes the beads export to the dedicated sync branch.
//
//   bun run publish-beads.ts [--push] [--dry-run]
//
// The Dolt database is authoritative and syncs over refs/dolt/data. The readable
// mirror lives on beads-sync as a compressed export (0.1.0-draft.1): gzipped
// JSONL, a small issue index, and a manifest with checksums. Attachment objects
// under .beads/objects/ are carried forward from the parent tree.
//
// The branch is written with git plumbing rather than by checking it out, so
// publishing never disturbs the working tree and works the same from a linked
// worktree. It shares no history with main and is not meant to be merged.
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	GITHUB_BLOB_LIMIT_BYTES,
	MIRROR_PATHS,
	buildIssueIndex,
	buildManifest,
	compressExport,
	countIssues,
	type MirrorManifest,
	validateBlobSizes,
} from "./beads-mirror-codec.ts";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const BRANCH = "beads-sync";
const INTERACTIONS_PATH = ".beads/interactions.jsonl";

export type MirrorFile = {
	path: string;
	bytes: Buffer;
};

export type MirrorPublication = {
	files: MirrorFile[];
	removePaths: string[];
	issueCount: number;
	manifest: MirrorManifest;
};

export function buildMirrorPublication(
	exportText: string,
	extraFiles: MirrorFile[] = [],
): MirrorPublication {
	const exportBytes = Buffer.from(exportText, "utf8");
	const gzipBytes = compressExport(exportBytes);
	const issueCount = countIssues(exportText);
	const indexText = buildIssueIndex(exportText);
	const manifest = buildManifest({
		exportBytes,
		gzipBytes,
		indexText,
		issueCount,
	});
	const files: MirrorFile[] = [
		{ path: MIRROR_PATHS.gzip, bytes: gzipBytes },
		{ path: MIRROR_PATHS.index, bytes: Buffer.from(indexText, "utf8") },
		{
			path: MIRROR_PATHS.manifest,
			bytes: Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8"),
		},
		...extraFiles,
	];
	validateBlobSizes(files.map((file) => ({ path: file.path, bytes: file.bytes.byteLength })));
	return {
		files,
		removePaths: [MIRROR_PATHS.legacyExport, INTERACTIONS_PATH],
		issueCount,
		manifest,
	};
}

export function choosePublishParent(input: {
	local: string | null;
	remote: string | null;
	localHasOversizedUnpublished: boolean;
	localIsAncestorOfRemote?: boolean;
	remoteIsAncestorOfLocal?: boolean;
}): string | null {
	const { local, remote } = input;
	if (input.localHasOversizedUnpublished) {
		if (remote === null) {
			throw new Error(
				`${BRANCH} local tip has oversized unpublished blobs and origin/${BRANCH} is missing; restore the last published tip before publishing`,
			);
		}
		return remote;
	}
	if (local === null) return remote;
	if (remote === null) return local;
	if (local === remote) return local;
	if (input.localIsAncestorOfRemote) return remote;
	if (input.remoteIsAncestorOfLocal) return local;
	throw new Error(
		`${BRANCH} and origin/${BRANCH} have diverged, so publishing would discard one of them`,
	);
}

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

function blobSizeAt(commit: string, filePath: string): number | null {
	const result = Bun.spawnSync(
		["git", "cat-file", "-s", `${commit}:${filePath}`],
		{ cwd: repositoryRoot, stderr: "pipe" },
	);
	if (result.exitCode !== 0) return null;
	const size = Number(result.stdout.toString().trim());
	return Number.isFinite(size) ? size : null;
}

function commitHasOversizedMirrorBlob(commit: string): boolean {
	for (const filePath of [MIRROR_PATHS.legacyExport, MIRROR_PATHS.gzip]) {
		const size = blobSizeAt(commit, filePath);
		if (size !== null && size >= GITHUB_BLOB_LIMIT_BYTES) return true;
	}
	return false;
}

function localHasOversizedUnpublished(
	local: string | null,
	remote: string | null,
): boolean {
	if (local === null) return false;
	if (remote !== null && local === remote) return false;
	if (remote !== null && isAncestor(remote, local)) {
		// Walk commits remote..local; any oversized mirror blob blocks push.
		const range = git(["rev-list", `${remote}..${local}`]);
		for (const commit of range.split("\n").filter(Boolean)) {
			if (commitHasOversizedMirrorBlob(commit)) return true;
		}
		return false;
	}
	return commitHasOversizedMirrorBlob(local);
}

function resolveParent(): string | null {
	Bun.spawnSync(["git", "fetch", "--quiet", "origin", BRANCH], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});

	const local = resolve(`refs/heads/${BRANCH}`);
	const remote = resolve(`refs/remotes/origin/${BRANCH}`);

	try {
		return choosePublishParent({
			local,
			remote,
			localHasOversizedUnpublished: localHasOversizedUnpublished(local, remote),
			localIsAncestorOfRemote:
				local !== null && remote !== null ? isAncestor(local, remote) : false,
			remoteIsAncestorOfLocal:
				local !== null && remote !== null ? isAncestor(remote, local) : false,
		});
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		console.error(`error: ${message}`);
		if (message.includes("diverged")) {
			console.error("Reconcile them first:");
			console.error(`    git log --oneline ${BRANCH} origin/${BRANCH}`);
			console.error(
				`    git update-ref refs/heads/${BRANCH} origin/${BRANCH}   # keep the remote`,
			);
		}
		process.exit(1);
	}
}

function main() {
	const push = process.argv.includes("--push");
	const dryRun = process.argv.includes("--dry-run");

	const exported = Bun.spawnSync(["bd", "export"], {
		cwd: repositoryRoot,
		stderr: "pipe",
	});
	if (exported.exitCode !== 0) {
		console.error("error: could not read the beads database");
		console.error(exported.stderr.toString().trim());
		process.exit(1);
	}

	const exportText = exported.stdout.toString();
	let publication: MirrorPublication;
	try {
		publication = buildMirrorPublication(exportText);
	} catch (error) {
		console.error(`error: ${error instanceof Error ? error.message : error}`);
		process.exit(1);
	}

	const scratch = mkdtempSync(path.join(tmpdir(), "beads-publish-"));
	try {
		const entries: Array<[string, string]> = [];
		for (const file of publication.files) {
			const scratchFile = path.join(scratch, path.basename(file.path));
			writeFileSync(scratchFile, file.bytes);
			const blob = git(["hash-object", "-w", "--path", file.path, scratchFile]);
			entries.push([file.path, blob]);
		}

		const parentCommit = resolveParent();
		const indexFile = path.join(scratch, "index");
		const env = { GIT_INDEX_FILE: indexFile };
		if (parentCommit) {
			git(["read-tree", parentCommit], { env });
			for (const removePath of publication.removePaths) {
				git(["update-index", "--force-remove", removePath], { env });
			}
		}
		for (const [file, blob] of entries) {
			git(["update-index", "--add", "--cacheinfo", `100644,${blob},${file}`], {
				env,
			});
		}
		const tree = git(["write-tree"], { env });

		if (parentCommit) {
			const parentTree = git(["rev-parse", `${parentCommit}^{tree}`]);
			if (parentTree === tree) {
				console.log(
					`${BRANCH} is already up to date (${parentCommit.slice(0, 8)})`,
				);
				process.exit(0);
			}
		}

		const message = `chore(beads): publish ${publication.issueCount} issues (${publication.manifest.format_version})`;

		if (dryRun) {
			console.log(`would commit tree ${tree.slice(0, 8)} to ${BRANCH}`);
			console.log(
				`  parent:  ${parentCommit ? parentCommit.slice(0, 8) : "(new branch)"}`,
			);
			console.log(`  message: ${message}`);
			for (const [file] of entries) {
				const size = publication.files.find((f) => f.path === file)?.bytes
					.byteLength;
				console.log(`  ${file}${size !== undefined ? ` (${size} bytes)` : ""}`);
			}
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
		console.log(
			`  gzip ${publication.manifest.gzip.bytes} bytes; export ${publication.manifest.export.bytes} bytes`,
		);

		if (push) {
			git(["push", "origin", `refs/heads/${BRANCH}:refs/heads/${BRANCH}`]);
			console.log(`pushed ${BRANCH} to origin`);
		} else {
			console.log(`  push it with: git push origin ${BRANCH}`);
		}
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
}

if (import.meta.main) {
	main();
}
