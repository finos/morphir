import { describe, expect, test } from "bun:test";
import {
	GITHUB_BLOB_LIMIT_BYTES,
	MIRROR_PATHS,
	sha256Hex,
} from "./beads-mirror-codec.ts";
import {
	buildMirrorPublication,
	choosePublishParent,
} from "./publish-beads.ts";

const sampleExport =
	[
		JSON.stringify({ id: "morphir-a1", title: "Alpha", status: "open", priority: 2 }),
		JSON.stringify({ id: "morphir-b2", title: "Beta", status: "closed", priority: 1 }),
	].join("\n") + "\n";

describe("buildMirrorPublication", () => {
	test("emits gzip, index and manifest under the contract paths", () => {
		const publication = buildMirrorPublication(sampleExport);
		expect(publication.files.map((f) => f.path).sort()).toEqual(
			[MIRROR_PATHS.gzip, MIRROR_PATHS.index, MIRROR_PATHS.manifest].sort(),
		);
		expect(publication.removePaths).toContain(MIRROR_PATHS.legacyExport);
		expect(publication.issueCount).toBe(2);
		expect(publication.manifest.export.sha256).toBe(
			sha256Hex(Buffer.from(sampleExport, "utf8")),
		);
		for (const file of publication.files) {
			expect(file.bytes.byteLength).toBeLessThan(GITHUB_BLOB_LIMIT_BYTES);
		}
	});
});

describe("choosePublishParent", () => {
	test("prefers remote when local tip carries oversized unpublished blobs", () => {
		expect(
			choosePublishParent({
				local: "aaa",
				remote: "bbb",
				localHasOversizedUnpublished: true,
			}),
		).toBe("bbb");
	});

	test("keeps shared resolve rules when local is safe", () => {
		expect(
			choosePublishParent({
				local: "aaa",
				remote: null,
				localHasOversizedUnpublished: false,
			}),
		).toBe("aaa");
		expect(
			choosePublishParent({
				local: null,
				remote: "bbb",
				localHasOversizedUnpublished: false,
			}),
		).toBe("bbb");
		expect(
			choosePublishParent({
				local: "aaa",
				remote: "bbb",
				localHasOversizedUnpublished: false,
				localIsAncestorOfRemote: true,
			}),
		).toBe("bbb");
		expect(
			choosePublishParent({
				local: "aaa",
				remote: "bbb",
				localHasOversizedUnpublished: false,
				remoteIsAncestorOfLocal: true,
			}),
		).toBe("aaa");
	});

	test("refuses diverged tips when local is not oversized", () => {
		expect(() =>
			choosePublishParent({
				local: "aaa",
				remote: "bbb",
				localHasOversizedUnpublished: false,
			}),
		).toThrow(/diverged/i);
	});
});
