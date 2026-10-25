import { createHash } from "node:crypto";
import { describe, expect, test } from "bun:test";
import {
	GITHUB_BLOB_LIMIT_BYTES,
	MIRROR_FORMAT_VERSION,
	MIRROR_PATHS,
	buildIssueIndex,
	buildManifest,
	compressExport,
	decompressExport,
	parseManifest,
	sha256Hex,
	validateBlobSizes,
} from "./beads-mirror-codec.ts";

const sampleExport = [
	JSON.stringify({
		id: "morphir-a1",
		title: "Alpha",
		status: "open",
		priority: 2,
		description: "keep me",
	}),
	JSON.stringify({
		id: "morphir-b2",
		title: "Beta",
		status: "closed",
		priority: 1,
		design: "<html>design</html>",
	}),
].join("\n") + "\n";

describe("beads mirror codec", () => {
	test("format version is SemVer 0.1.0-draft.1", () => {
		expect(MIRROR_FORMAT_VERSION).toBe("0.1.0-draft.1");
	});

	test("gzip round-trip preserves exact export bytes", () => {
		const raw = Buffer.from(sampleExport, "utf8");
		const gzipped = compressExport(raw);
		expect(gzipped.byteLength).toBeLessThan(raw.byteLength);
		const restored = decompressExport(gzipped);
		expect(Buffer.compare(restored, raw)).toBe(0);
	});

	test("decompress refuses truncated and corrupt payloads", () => {
		const gzipped = compressExport(Buffer.from(sampleExport, "utf8"));
		expect(() => decompressExport(gzipped.subarray(0, 8))).toThrow(/corrupt|truncat/i);
		const flipped = Buffer.from(gzipped);
		flipped[flipped.length - 1] ^= 0xff;
		expect(() => decompressExport(flipped)).toThrow(/corrupt|truncat/i);
	});

	test("manifest records version, counts, lengths and checksums", () => {
		const raw = Buffer.from(sampleExport, "utf8");
		const gzipped = compressExport(raw);
		const index = buildIssueIndex(sampleExport);
		const manifest = buildManifest({
			exportBytes: raw,
			gzipBytes: gzipped,
			indexText: index,
			issueCount: 2,
		});
		expect(manifest.format_version).toBe("0.1.0-draft.1");
		expect(manifest.issue_count).toBe(2);
		expect(manifest.export.sha256).toBe(sha256Hex(raw));
		expect(manifest.export.bytes).toBe(raw.byteLength);
		expect(manifest.gzip.sha256).toBe(sha256Hex(gzipped));
		expect(manifest.gzip.bytes).toBe(gzipped.byteLength);
		expect(manifest.index.sha256).toBe(sha256Hex(Buffer.from(index, "utf8")));
		expect(parseManifest(JSON.stringify(manifest))).toEqual(manifest);
	});

	test("parseManifest rejects unknown or malformed versions", () => {
		expect(() =>
			parseManifest(
				JSON.stringify({
					format_version: "not-a-version",
					issue_count: 1,
					export: { bytes: 1, sha256: "a".repeat(64) },
					gzip: { bytes: 1, sha256: "b".repeat(64) },
					index: { bytes: 1, sha256: "c".repeat(64) },
				}),
			),
		).toThrow(/semver|version/i);
		expect(() =>
			parseManifest(
				JSON.stringify({
					format_version: "0.2.0",
					issue_count: 1,
					export: { bytes: 1, sha256: "a".repeat(64) },
					gzip: { bytes: 1, sha256: "b".repeat(64) },
					index: { bytes: 1, sha256: "c".repeat(64) },
				}),
			),
		).toThrow(/unsupported/i);
	});

	test("issue index is compact and ordered by id", () => {
		const index = buildIssueIndex(sampleExport);
		const lines = index.trim().split("\n").map((line) => JSON.parse(line));
		expect(lines).toEqual([
			{ id: "morphir-a1", title: "Alpha", status: "open", priority: 2 },
			{ id: "morphir-b2", title: "Beta", status: "closed", priority: 1 },
		]);
		expect(index.includes("design")).toBe(false);
		expect(index.includes("description")).toBe(false);
	});

	test("validateBlobSizes rejects any entry at or over the GitHub limit", () => {
		expect(GITHUB_BLOB_LIMIT_BYTES).toBe(100 * 1024 * 1024);
		expect(() =>
			validateBlobSizes([
				{ path: MIRROR_PATHS.gzip, bytes: GITHUB_BLOB_LIMIT_BYTES },
			]),
		).toThrow(/GitHub|100|limit/i);
		expect(() =>
			validateBlobSizes([
				{ path: MIRROR_PATHS.gzip, bytes: GITHUB_BLOB_LIMIT_BYTES - 1 },
			]),
		).not.toThrow();
	});

	test("sha256Hex matches Node crypto", () => {
		const bytes = Buffer.from("hello", "utf8");
		expect(sha256Hex(bytes)).toBe(
			createHash("sha256").update(bytes).digest("hex"),
		);
	});
});
