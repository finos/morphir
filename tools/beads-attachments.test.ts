import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { describe, expect, test } from "bun:test";
import {
	attachmentObjectPath,
	buildAttachmentObject,
	inventoryDataUriAttachments,
	rewriteDataUriReferences,
} from "./beads-attachments.ts";

function dataUri(mime: string, bytes: Buffer): string {
	return `data:${mime};base64,${bytes.toString("base64")}`;
}

describe("inventoryDataUriAttachments", () => {
	test("extracts recognized base64 data URIs with exact bytes and hashes", () => {
		const payload = Buffer.alloc(80, 7);
		const html = `<a download href="${dataUri("application/gzip", payload)}">dl</a>`;
		const inventory = inventoryDataUriAttachments([
			{ issueId: "morphir-x", field: "design", text: html },
		]);
		expect(inventory.attachments).toHaveLength(1);
		const item = inventory.attachments[0]!;
		expect(item.issueId).toBe("morphir-x");
		expect(item.field).toBe("design");
		expect(item.mediaType).toBe("application/gzip");
		expect(Buffer.compare(item.bytes, payload)).toBe(0);
		expect(item.sha256).toBe(createHash("sha256").update(payload).digest("hex"));
		expect(inventory.unknown).toEqual([]);
	});

	test("deduplicates identical decoded payloads", () => {
		const payload = Buffer.alloc(96, 9);
		const uri = dataUri("application/json", payload);
		const inventory = inventoryDataUriAttachments([
			{ issueId: "a", field: "design", text: `one ${uri} two ${uri}` },
			{ issueId: "b", field: "design", text: uri },
		]);
		expect(inventory.attachments).toHaveLength(3);
		expect(new Set(inventory.attachments.map((a) => a.sha256)).size).toBe(1);
	});

	test("leaves unknown schemes untouched and reports them", () => {
		const text = `weird data:application/x-unknown;base64,${"A".repeat(80)} and keep`;
		const inventory = inventoryDataUriAttachments([
			{ issueId: "a", field: "design", text },
		]);
		expect(inventory.attachments).toHaveLength(0);
		expect(inventory.unknown.length).toBe(1);
		expect(inventory.unknown[0]?.mediaType).toBe("application/x-unknown");
	});
});

describe("buildAttachmentObject / rewrite", () => {
	test("stores already-compressed gzip bytes unchanged", () => {
		const raw = Buffer.from("archive-body");
		const gzipped = gzipSync(raw);
		const object = buildAttachmentObject({
			sha256: createHash("sha256").update(gzipped).digest("hex"),
			bytes: gzipped,
			mediaType: "application/gzip",
		});
		expect(Buffer.compare(object.content, gzipped)).toBe(0);
		expect(object.relativePath).toBe(
			attachmentObjectPath(object.meta.sha256, object.meta.fileName),
		);
		expect(object.meta.compressed).toBe(false);
	});

	test("rewrite replaces only matched URIs and refuses stale source text", () => {
		const payload = Buffer.alloc(64, 3);
		const uri = dataUri("image/png", payload);
		const html = `<p>keep</p><img src="${uri}"/><p>also</p>`;
		const inventory = inventoryDataUriAttachments([
			{ issueId: "a", field: "design", text: html },
		]);
		const object = buildAttachmentObject({
			sha256: inventory.attachments[0]!.sha256,
			bytes: payload,
			mediaType: "image/png",
		});
		const rewritten = rewriteDataUriReferences({
			sourceText: html,
			replacements: [
				{
					exactUri: uri,
					href: object.relativePath,
				},
			],
		});
		expect(rewritten).toContain("<p>keep</p>");
		expect(rewritten).toContain(`src="${object.relativePath}"`);
		expect(rewritten).not.toContain("data:image/png");
		expect(() =>
			rewriteDataUriReferences({
				sourceText: html + "changed",
				expectedSourceText: html,
				replacements: [{ exactUri: uri, href: object.relativePath }],
			}),
		).toThrow(/stale|changed|concurrent/i);
	});

	test("duplicate exact URIs rewrite once", () => {
		const payload = Buffer.alloc(64, 4);
		const uri = dataUri("image/svg+xml", payload);
		const html = `<img src="${uri}"/><img src="${uri}"/>`;
		const href = ".beads/objects/abcd/image.svg";
		const rewritten = rewriteDataUriReferences({
			sourceText: html,
			replacements: [
				{ exactUri: uri, href },
				{ exactUri: uri, href },
			],
		});
		expect(rewritten).toBe(`<img src="${href}"/><img src="${href}"/>`);
		expect(rewritten.includes("data:")).toBe(false);
	});
});
