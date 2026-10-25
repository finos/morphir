// Shared codec for the beads-sync readable mirror.
//
// Contract version 0.1.0-draft.1: gzipped full export, compact index, and a
// manifest with checksums. Publish and drift-check both import this module so
// they cannot disagree on paths or hashing.
import { createHash } from "node:crypto";
import { gunzipSync, gzipSync } from "node:zlib";
import { format, parse } from "@std/semver";

export const MIRROR_FORMAT_VERSION = "0.1.0-draft.1";

/** GitHub hard limit for a single blob. Blobs must be strictly smaller. */
export const GITHUB_BLOB_LIMIT_BYTES = 100 * 1024 * 1024;

export const MIRROR_PATHS = {
	gzip: ".beads/issues.jsonl.gz",
	index: ".beads/issues.index.jsonl",
	manifest: ".beads/mirror.manifest.json",
	/** Legacy plain export — readers still understand it; new publishes omit it. */
	legacyExport: ".beads/issues.jsonl",
	objectsDir: ".beads/objects",
} as const;

export type DigestLength = {
	bytes: number;
	sha256: string;
};

export type MirrorManifest = {
	format_version: string;
	issue_count: number;
	export: DigestLength;
	gzip: DigestLength;
	index: DigestLength;
};

const SUPPORTED_FORMAT_VERSIONS = new Set([MIRROR_FORMAT_VERSION]);

export function sha256Hex(bytes: Uint8Array): string {
	return createHash("sha256").update(bytes).digest("hex");
}

export function compressExport(raw: Uint8Array): Buffer {
	return gzipSync(raw, { level: 6 });
}

export function decompressExport(gzipped: Uint8Array): Buffer {
	try {
		return gunzipSync(gzipped);
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		throw new Error(`corrupt or truncated gzip export: ${detail}`);
	}
}

type IndexFields = {
	id: string;
	title?: unknown;
	status?: unknown;
	priority?: unknown;
};

export function buildIssueIndex(exportText: string): string {
	const rows: IndexFields[] = [];
	for (const line of exportText.split("\n")) {
		if (line.trim() === "") continue;
		const record = JSON.parse(line) as IndexFields;
		if (typeof record.id !== "string") continue;
		rows.push({
			id: record.id,
			title: record.title,
			status: record.status,
			priority: record.priority,
		});
	}
	rows.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
	return rows.map((row) => JSON.stringify(row)).join("\n") + (rows.length > 0 ? "\n" : "");
}

export function buildManifest(input: {
	exportBytes: Uint8Array;
	gzipBytes: Uint8Array;
	indexText: string;
	issueCount: number;
}): MirrorManifest {
	const indexBytes = Buffer.from(input.indexText, "utf8");
	return {
		format_version: MIRROR_FORMAT_VERSION,
		issue_count: input.issueCount,
		export: { bytes: input.exportBytes.byteLength, sha256: sha256Hex(input.exportBytes) },
		gzip: { bytes: input.gzipBytes.byteLength, sha256: sha256Hex(input.gzipBytes) },
		index: { bytes: indexBytes.byteLength, sha256: sha256Hex(indexBytes) },
	};
}

function requireDigest(value: unknown, label: string): DigestLength {
	if (value === null || typeof value !== "object") {
		throw new Error(`manifest ${label} is missing`);
	}
	const record = value as Record<string, unknown>;
	if (typeof record.bytes !== "number" || !Number.isFinite(record.bytes)) {
		throw new Error(`manifest ${label}.bytes is invalid`);
	}
	if (typeof record.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(record.sha256)) {
		throw new Error(`manifest ${label}.sha256 is invalid`);
	}
	return { bytes: record.bytes, sha256: record.sha256 };
}

export function parseManifest(text: string): MirrorManifest {
	let raw: unknown;
	try {
		raw = JSON.parse(text);
	} catch (error) {
		throw new Error(`manifest is not JSON: ${error}`);
	}
	if (raw === null || typeof raw !== "object") {
		throw new Error("manifest root must be an object");
	}
	const record = raw as Record<string, unknown>;
	if (typeof record.format_version !== "string") {
		throw new Error("manifest format_version is missing");
	}
	let parsed;
	try {
		parsed = parse(record.format_version);
	} catch {
		throw new Error(`manifest format_version is not SemVer: ${record.format_version}`);
	}
	if (parsed === undefined) {
		throw new Error(`manifest format_version is not SemVer: ${record.format_version}`);
	}
	const canonical = format(parsed);
	if (canonical !== record.format_version) {
		throw new Error(
			`manifest format_version must be canonical SemVer (${canonical}), got ${record.format_version}`,
		);
	}
	if (!SUPPORTED_FORMAT_VERSIONS.has(canonical)) {
		throw new Error(`unsupported mirror format version: ${canonical}`);
	}
	if (typeof record.issue_count !== "number" || !Number.isFinite(record.issue_count)) {
		throw new Error("manifest issue_count is invalid");
	}
	return {
		format_version: canonical,
		issue_count: record.issue_count,
		export: requireDigest(record.export, "export"),
		gzip: requireDigest(record.gzip, "gzip"),
		index: requireDigest(record.index, "index"),
	};
}

export function validateBlobSizes(
	entries: Array<{ path: string; bytes: number }>,
	limit = GITHUB_BLOB_LIMIT_BYTES,
): void {
	for (const entry of entries) {
		if (entry.bytes >= limit) {
			throw new Error(
				`${entry.path} is ${entry.bytes} bytes; GitHub rejects blobs at or over the ${limit} byte limit`,
			);
		}
	}
}

/** Count issue lines in an export (skips blank lines and memory records without id). */
export function countIssues(exportText: string): number {
	let count = 0;
	for (const line of exportText.split("\n")) {
		if (line.trim() === "") continue;
		try {
			const record = JSON.parse(line) as { id?: unknown };
			if (typeof record.id === "string") count += 1;
		} catch {
			// Malformed lines are counted by callers that parse strictly elsewhere.
		}
	}
	return count;
}

export function verifyGzipAgainstManifest(
	gzipped: Uint8Array,
	manifest: MirrorManifest,
): Buffer {
	if (gzipped.byteLength !== manifest.gzip.bytes) {
		throw new Error(
			`gzip length ${gzipped.byteLength} does not match manifest ${manifest.gzip.bytes}`,
		);
	}
	const gzipHash = sha256Hex(gzipped);
	if (gzipHash !== manifest.gzip.sha256) {
		throw new Error(`gzip sha256 ${gzipHash} does not match manifest ${manifest.gzip.sha256}`);
	}
	const raw = decompressExport(gzipped);
	if (raw.byteLength !== manifest.export.bytes) {
		throw new Error(
			`decompressed export length ${raw.byteLength} does not match manifest ${manifest.export.bytes}`,
		);
	}
	const exportHash = sha256Hex(raw);
	if (exportHash !== manifest.export.sha256) {
		throw new Error(
			`decompressed export sha256 ${exportHash} does not match manifest ${manifest.export.sha256}`,
		);
	}
	return raw;
}
