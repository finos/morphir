import { describe, expect, test } from "bun:test";
import {
	buildMirrorPublication,
} from "./publish-beads.ts";
import {
	loadTrackedExportText,
	type TrackedMirrorSource,
} from "./check-beads-drift.ts";
import { MIRROR_PATHS, sha256Hex } from "./beads-mirror-codec.ts";

const sampleExport =
	[
		JSON.stringify({ id: "morphir-a1", title: "Alpha", status: "open", priority: 2 }),
		JSON.stringify({ id: "morphir-b2", title: "Beta", status: "closed", priority: 1 }),
	].join("\n") + "\n";

describe("loadTrackedExportText", () => {
	test("reads legacy plain JSONL", () => {
		const source: TrackedMirrorSource = {
			kind: "legacy",
			text: sampleExport,
			label: "test:legacy",
		};
		const loaded = loadTrackedExportText(source);
		expect(loaded).toBe(sampleExport);
	});

	test("decompresses gzip layout and verifies manifest checksums", () => {
		const publication = buildMirrorPublication(sampleExport);
		const byPath = Object.fromEntries(
			publication.files.map((file) => [file.path, file.bytes]),
		);
		const source: TrackedMirrorSource = {
			kind: "compressed",
			label: "test:compressed",
			gzip: byPath[MIRROR_PATHS.gzip]!,
			manifestText: byPath[MIRROR_PATHS.manifest]!.toString("utf8"),
		};
		const loaded = loadTrackedExportText(source);
		expect(loaded).toBe(sampleExport);
		expect(sha256Hex(Buffer.from(loaded, "utf8"))).toBe(
			publication.manifest.export.sha256,
		);
	});

	test("refuses a truncated gzip payload", () => {
		const publication = buildMirrorPublication(sampleExport);
		const byPath = Object.fromEntries(
			publication.files.map((file) => [file.path, file.bytes]),
		);
		expect(() =>
			loadTrackedExportText({
				kind: "compressed",
				label: "test:truncated",
				gzip: byPath[MIRROR_PATHS.gzip]!.subarray(0, 12),
				manifestText: byPath[MIRROR_PATHS.manifest]!.toString("utf8"),
			}),
		).toThrow(/corrupt|truncat|sha256|length/i);
	});
});
