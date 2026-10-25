// Inventories recognized data-URI evidence in issue design fields, publishes
// hash-named objects onto beads-sync, verifies them, then rewrites Dolt fields
// with a compare-and-update guard.
//
//   bun run tools/migrate-beads-attachments.ts [--apply] [--push-mirror]
//
// Default is dry-run: write inventory + receipt under .dev/u8tx-recovery/.
import {
	mkdirSync,
	mkdtempSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import {
	inventoryDataUriAttachments,
	rewriteDataUriReferences,
	uniqueObjects,
	type AttachmentObject,
} from "./beads-attachments.ts";
import { MIRROR_PATHS, sha256Hex } from "./beads-mirror-codec.ts";
import {
	buildMirrorPublication,
	type MirrorFile,
} from "./publish-beads.ts";

const repositoryRoot = path.dirname(
	path.dirname(fileURLToPath(import.meta.url)),
);
const BD = ["bd", "-C", "/Users/damian/code/github/finos/morphir"];
const apply = process.argv.includes("--apply");
const pushMirror = process.argv.includes("--push-mirror");
const recoveryDir = path.join(repositoryRoot, ".dev", "u8tx-recovery");

type IssueRecord = Record<string, unknown> & { id: string };

function run(
	command: string[],
	options: { cwd?: string; env?: Record<string, string>; input?: Buffer } = {},
) {
	const result = Bun.spawnSync(command, {
		cwd: options.cwd ?? repositoryRoot,
		env: { ...process.env, ...options.env },
		stdin: options.input ? options.input : "ignore",
		stderr: "pipe",
		stdout: "pipe",
	});
	if (result.exitCode !== 0) {
		throw new Error(
			`${command.join(" ")} failed: ${result.stderr.toString().trim()}`,
		);
	}
	return result.stdout;
}

function git(args: string[], env?: Record<string, string>) {
	return run(["git", ...args], { env }).toString("utf8").trim();
}

function exportIssues(): IssueRecord[] {
	const text = run([...BD, "export"]).toString("utf8");
	const issues: IssueRecord[] = [];
	for (const line of text.split("\n")) {
		if (line.trim() === "") continue;
		const record = JSON.parse(line) as IssueRecord;
		if (typeof record.id === "string") issues.push(record);
	}
	return issues;
}

function objectFiles(objects: AttachmentObject[]): MirrorFile[] {
	const files: MirrorFile[] = [];
	for (const object of objects) {
		files.push({ path: object.relativePath, bytes: object.content });
		files.push({
			path: object.metaPath,
			bytes: Buffer.from(`${JSON.stringify(object.meta, null, 2)}\n`, "utf8"),
		});
	}
	return files;
}

function publishTree(files: MirrorFile[], message: string): string {
	const scratch = mkdtempSync(path.join(tmpdir(), "beads-attach-pub-"));
	try {
		Bun.spawnSync(["git", "fetch", "--quiet", "origin", "beads-sync"], {
			cwd: repositoryRoot,
			stderr: "pipe",
		});
		const remoteResult = Bun.spawnSync(
			["git", "rev-parse", "--verify", "-q", "refs/remotes/origin/beads-sync"],
			{ cwd: repositoryRoot, stderr: "pipe" },
		);
		const localResult = Bun.spawnSync(
			["git", "rev-parse", "--verify", "-q", "refs/heads/beads-sync"],
			{ cwd: repositoryRoot, stderr: "pipe" },
		);
		const remote =
			remoteResult.exitCode === 0 ? remoteResult.stdout.toString().trim() : null;
		const local =
			localResult.exitCode === 0 ? localResult.stdout.toString().trim() : null;
		// Prefer a safe local tip so previously published .beads/objects survive.
		// Fall back to remote when local is missing. Oversized unpublished local
		// tips are reset to remote by publish-beads before ordinary publishes.
		const parent = local ?? remote;

		const indexFile = path.join(scratch, "index");
		const env = { GIT_INDEX_FILE: indexFile };
		if (parent) {
			git(["read-tree", parent], env);
			git(["update-index", "--force-remove", MIRROR_PATHS.legacyExport], env);
			git(["update-index", "--force-remove", ".beads/interactions.jsonl"], env);
		}
		for (const file of files) {
			const scratchFile = path.join(scratch, file.path.replaceAll("/", "__"));
			mkdirSync(path.dirname(scratchFile), { recursive: true });
			writeFileSync(scratchFile, file.bytes);
			const blob = git(
				["hash-object", "-w", "--path", file.path, scratchFile],
				env,
			);
			git(
				["update-index", "--add", "--cacheinfo", `100644,${blob},${file.path}`],
				env,
			);
		}
		const tree = git(["write-tree"], env);
		const commit = git([
			"commit-tree",
			tree,
			...(parent ? ["-p", parent] : []),
			"-m",
			message,
		]);
		git(["update-ref", "refs/heads/beads-sync", commit]);
		return commit;
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
}

function verifyObjectsFromGit(objects: AttachmentObject[], commit: string) {
	for (const object of objects) {
		const bytes = run(["git", "show", `${commit}:${object.relativePath}`]);
		const contentHash = sha256Hex(bytes);
		if (contentHash !== object.meta.contentSha256) {
			throw new Error(
				`object ${object.relativePath} content sha ${contentHash} != ${object.meta.contentSha256}`,
			);
		}
		const original = object.meta.compressed ? gunzipSync(bytes) : bytes;
		if (sha256Hex(original) !== object.meta.sha256) {
			throw new Error(`object ${object.relativePath} failed original hash check`);
		}
	}
}

function compareAndUpdateDesign(
	issueId: string,
	expected: string,
	next: string,
): "updated" | "skipped-stale" {
	const shown = JSON.parse(
		run([...BD, "show", issueId, "--json"]).toString("utf8"),
	) as Array<{ design?: string }> | { design?: string };
	const issue = Array.isArray(shown) ? shown[0] : shown;
	const current = issue?.design ?? "";
	if (current !== expected) {
		return "skipped-stale";
	}
	const scratch = mkdtempSync(path.join(tmpdir(), "beads-design-"));
	try {
		const file = path.join(scratch, "design.html");
		writeFileSync(file, next);
		run([...BD, "update", issueId, "--design-file", file]);
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
	return "updated";
}

function main() {
	mkdirSync(recoveryDir, { recursive: true });
	const issues = exportIssues();
	const fields = issues
		.filter((issue) => typeof issue.design === "string" && issue.design.includes("data:"))
		.map((issue) => ({
			issueId: issue.id,
			field: "design",
			text: issue.design as string,
		}));

	const inventory = inventoryDataUriAttachments(fields);
	const objects = uniqueObjects(inventory.attachments);
	const inventoryPath = path.join(recoveryDir, "attachment-inventory.json");
	writeFileSync(
		inventoryPath,
		`${JSON.stringify(
			{
				issueFieldsScanned: fields.length,
				occurrences: inventory.attachments.length,
				uniqueObjects: objects.length,
				unknown: inventory.unknown,
				attachments: inventory.attachments.map((a) => ({
					issueId: a.issueId,
					field: a.field,
					mediaType: a.mediaType,
					sha256: a.sha256,
					bytes: a.bytes.byteLength,
				})),
				objects: objects.map((o) => o.meta),
			},
			null,
			2,
		)}\n`,
	);

	console.log(
		`inventory: ${inventory.attachments.length} occurrence(s), ${objects.length} unique object(s), ${inventory.unknown.length} unknown`,
	);
	console.log(`wrote ${inventoryPath}`);

	if (!apply) {
		console.log("dry-run only; pass --apply to publish objects and rewrite designs");
		return;
	}

	const exportText = `${issues.map((issue) => JSON.stringify(issue)).join("\n")}\n`;
	// Step A: publish current mirror + objects together so objects are recoverable.
	const publication = buildMirrorPublication(exportText, objectFiles(objects));
	const commit = publishTree(
		publication.files,
		`chore(beads): publish ${publication.issueCount} issues with ${objects.length} attachments (${publication.manifest.format_version})`,
	);
	console.log(`beads-sync updated to ${commit.slice(0, 8)} (objects + mirror)`);
	verifyObjectsFromGit(objects, commit);
	console.log("verified attachment content hashes from git");

	const byHash = new Map(objects.map((object) => [object.meta.sha256, object]));
	const rollback: Array<{
		issueId: string;
		field: string;
		beforeSha256: string;
		afterSha256: string;
		status: string;
	}> = [];

	const byIssue = new Map<string, typeof inventory.attachments>();
	for (const item of inventory.attachments) {
		const list = byIssue.get(item.issueId) ?? [];
		list.push(item);
		byIssue.set(item.issueId, list);
	}

	for (const [issueId, items] of byIssue) {
		const source = fields.find((f) => f.issueId === issueId)?.text;
		if (source === undefined) continue;
		const replacements = items.map((item) => {
			const object = byHash.get(item.sha256);
			if (object === undefined) {
				throw new Error(`missing object for ${item.sha256}`);
			}
			return { exactUri: item.exactUri, href: object.relativePath };
		});
		const next = rewriteDataUriReferences({
			sourceText: source,
			expectedSourceText: source,
			replacements,
		});
		const status = compareAndUpdateDesign(issueId, source, next);
		rollback.push({
			issueId,
			field: "design",
			beforeSha256: sha256Hex(Buffer.from(source, "utf8")),
			afterSha256: sha256Hex(Buffer.from(next, "utf8")),
			status,
		});
		console.log(`${issueId}: ${status}`);
	}

	const receiptPath = path.join(recoveryDir, "migration-receipt.json");
	writeFileSync(
		receiptPath,
		`${JSON.stringify(
			{
				created_at: new Date().toISOString(),
				mirror_commit: commit,
				objects: objects.map((o) => o.meta),
				rollback,
				inventory_path: inventoryPath,
			},
			null,
			2,
		)}\n`,
	);
	console.log(`wrote ${receiptPath}`);

	// Snapshot pre-rewrite designs for offline rollback.
	const rollbackDir = path.join(recoveryDir, "design-rollback");
	mkdirSync(rollbackDir, { recursive: true });
	for (const field of fields) {
		writeFileSync(path.join(rollbackDir, `${field.issueId}.design.html`), field.text);
	}

	run([...BD, "dolt", "commit", "-m", "morphir-u8tx: extract recognized design data-URI attachments"]);
	try {
		run([...BD, "dolt", "push"]);
	} catch (error) {
		console.error(`warning: dolt push failed: ${error}`);
	}

	// Republish mirror from live export after rewrites.
	const republished = run(["bun", "run", path.join(repositoryRoot, "tools", "publish-beads.ts")]);
	console.log(republished.toString("utf8").trim());

	if (pushMirror) {
		git(["push", "origin", "refs/heads/beads-sync:refs/heads/beads-sync"]);
		console.log("pushed beads-sync to origin");
	} else {
		console.log("mirror ready locally; push with: git push origin beads-sync");
	}

	// Offline bundle: records + objects (no .dev dependency for consumers of the bundle).
	const bundleDir = path.join(recoveryDir, "offline-bundle");
	rmSync(bundleDir, { recursive: true, force: true });
	mkdirSync(path.join(bundleDir, MIRROR_PATHS.objectsDir), { recursive: true });
	for (const object of objects) {
		const contentOut = path.join(bundleDir, object.relativePath);
		const metaOut = path.join(bundleDir, object.metaPath);
		mkdirSync(path.dirname(contentOut), { recursive: true });
		writeFileSync(contentOut, object.content);
		writeFileSync(metaOut, `${JSON.stringify(object.meta, null, 2)}\n`);
	}
	writeFileSync(
		path.join(bundleDir, "README.md"),
		`# beads attachment offline bundle\n\nObjects are under \`${MIRROR_PATHS.objectsDir}/<sha256>/\`.\nMirror commit: ${commit}\n`,
	);
	console.log(`offline bundle at ${bundleDir}`);
}

main();
