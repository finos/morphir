// Recognized embedded evidence extraction for beads design HTML.
//
// Only known data-URI media types are rewritten. Unknown types are reported and
// left unchanged. Attachment content is addressed by SHA-256 of the exact
// decoded bytes and stored under .beads/objects/<sha256>/.
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { MIRROR_PATHS } from "./beads-mirror-codec.ts";

const RECOGNIZED_MEDIA = new Set([
	"application/gzip",
	"application/x-gzip",
	"application/zip",
	"application/x-tar",
	"application/octet-stream",
	"application/json",
	"text/plain",
	"image/png",
	"image/jpeg",
	"image/jpg",
	"image/gif",
	"image/webp",
	"image/svg+xml",
	"font/woff",
	"font/woff2",
	"font/ttf",
	"font/otf",
]);

// data:[<mediatype>][;base64],<data> — require base64 and a non-trivial payload.
// Payload excludes whitespace so adjacent URIs in HTML do not merge. Callers
// that fold base64 across lines should normalize before inventory.
const DATA_URI =
	/data:([a-z0-9!#$&\-\^_+.]+\/[a-z0-9!#$&\-\^_+.]+)?((?:;[a-z0-9!#$&\-\^_+=.-]+)*)?(;base64)?,([A-Za-z0-9+/=]+)/gi;

export type FieldText = {
	issueId: string;
	field: string;
	text: string;
};

export type AttachmentOccurrence = {
	issueId: string;
	field: string;
	mediaType: string;
	bytes: Buffer;
	sha256: string;
	exactUri: string;
	start: number;
	end: number;
};

export type UnknownOccurrence = {
	issueId: string;
	field: string;
	mediaType: string;
	payloadChars: number;
	exactUriPreview: string;
};

export type AttachmentInventory = {
	attachments: AttachmentOccurrence[];
	unknown: UnknownOccurrence[];
};

export type AttachmentMeta = {
	sha256: string;
	bytes: number;
	mediaType: string;
	fileName: string;
	compressed: boolean;
	contentSha256: string;
};

export type AttachmentObject = {
	meta: AttachmentMeta;
	content: Buffer;
	relativePath: string;
	metaPath: string;
};

function sha256Hex(bytes: Uint8Array): string {
	return createHash("sha256").update(bytes).digest("hex");
}

function looksLikeGzip(bytes: Uint8Array): boolean {
	return bytes.byteLength >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
}

function extensionFor(mediaType: string, bytes: Uint8Array): string {
	switch (mediaType) {
		case "application/gzip":
		case "application/x-gzip":
			return "evidence.gz";
		case "application/zip":
			return "evidence.zip";
		case "application/x-tar":
			return "evidence.tar";
		case "application/json":
			return "evidence.json";
		case "text/plain":
			return "evidence.txt";
		case "image/png":
			return "image.png";
		case "image/jpeg":
		case "image/jpg":
			return "image.jpeg";
		case "image/gif":
			return "image.gif";
		case "image/webp":
			return "image.webp";
		case "image/svg+xml":
			return "image.svg";
		case "font/woff2":
			return "font.woff2";
		case "font/woff":
			return "font.woff";
		case "font/ttf":
			return "font.ttf";
		case "font/otf":
			return "font.otf";
		default:
			return looksLikeGzip(bytes) ? "evidence.gz" : "evidence.bin";
	}
}

export function attachmentObjectPath(sha256: string, fileName: string): string {
	return `${MIRROR_PATHS.objectsDir}/${sha256}/${fileName}`;
}

export function inventoryDataUriAttachments(
	fields: FieldText[],
): AttachmentInventory {
	const attachments: AttachmentOccurrence[] = [];
	const unknown: UnknownOccurrence[] = [];

	for (const field of fields) {
		DATA_URI.lastIndex = 0;
		let match: RegExpExecArray | null;
		while ((match = DATA_URI.exec(field.text)) !== null) {
			const mediaType = (match[1] ?? "").toLowerCase();
			const params = match[2] ?? "";
			const isBase64 = Boolean(match[3]) || /;base64/i.test(params);
			const payload = (match[4] ?? "").replace(/\s+/g, "");
			const exactUri = match[0]!;
			if (!isBase64 || payload.length < 64) continue;

			if (!RECOGNIZED_MEDIA.has(mediaType)) {
				unknown.push({
					issueId: field.issueId,
					field: field.field,
					mediaType: mediaType || "(missing)",
					payloadChars: payload.length,
					exactUriPreview: exactUri.slice(0, 96),
				});
				continue;
			}

			let bytes: Buffer;
			try {
				bytes = Buffer.from(payload, "base64");
			} catch {
				unknown.push({
					issueId: field.issueId,
					field: field.field,
					mediaType,
					payloadChars: payload.length,
					exactUriPreview: exactUri.slice(0, 96),
				});
				continue;
			}
			if (bytes.byteLength === 0) continue;

			attachments.push({
				issueId: field.issueId,
				field: field.field,
				mediaType,
				bytes,
				sha256: sha256Hex(bytes),
				exactUri,
				start: match.index,
				end: match.index + exactUri.length,
			});
		}
	}

	return { attachments, unknown };
}

export function buildAttachmentObject(input: {
	sha256: string;
	bytes: Buffer;
	mediaType: string;
}): AttachmentObject {
	const alreadyCompressed =
		looksLikeGzip(input.bytes) ||
		input.mediaType === "application/gzip" ||
		input.mediaType === "application/x-gzip" ||
		input.mediaType === "application/zip" ||
		input.mediaType === "image/png" ||
		input.mediaType === "image/jpeg" ||
		input.mediaType === "image/jpg" ||
		input.mediaType === "image/gif" ||
		input.mediaType === "image/webp" ||
		input.mediaType === "font/woff" ||
		input.mediaType === "font/woff2";

	let content = input.bytes;
	let compressed = false;
	if (!alreadyCompressed) {
		const gz = gzipSync(input.bytes, { level: 6 });
		if (gz.byteLength < input.bytes.byteLength) {
			content = gz;
			compressed = true;
		}
	}

	const fileName = compressed
		? `${extensionFor(input.mediaType, input.bytes)}.gz`
		: extensionFor(input.mediaType, input.bytes);

	const meta: AttachmentMeta = {
		sha256: input.sha256,
		bytes: input.bytes.byteLength,
		mediaType: input.mediaType,
		fileName,
		compressed,
		contentSha256: sha256Hex(content),
	};

	return {
		meta,
		content,
		relativePath: attachmentObjectPath(input.sha256, fileName),
		metaPath: attachmentObjectPath(input.sha256, "meta.json"),
	};
}

export function rewriteDataUriReferences(input: {
	sourceText: string;
	expectedSourceText?: string;
	replacements: Array<{ exactUri: string; href: string }>;
}): string {
	if (
		input.expectedSourceText !== undefined &&
		input.sourceText !== input.expectedSourceText
	) {
		throw new Error(
			"stale source field: concurrent edit detected; refusing rewrite",
		);
	}
	let out = input.sourceText;
	// One replacement per exact URI. Longest first so prefixes cannot mangle.
	const byUri = new Map<string, string>();
	for (const replacement of input.replacements) {
		const previous = byUri.get(replacement.exactUri);
		if (previous !== undefined && previous !== replacement.href) {
			throw new Error(
				`exact URI maps to both ${previous} and ${replacement.href}`,
			);
		}
		byUri.set(replacement.exactUri, replacement.href);
	}
	const ordered = [...byUri.entries()].sort((a, b) => b[0].length - a[0].length);
	for (const [exactUri, href] of ordered) {
		if (!out.includes(exactUri)) {
			throw new Error(
				`exact URI not found in source field while rewriting to ${href}`,
			);
		}
		out = out.split(exactUri).join(href);
	}
	return out;
}

export function uniqueObjects(
	attachments: AttachmentOccurrence[],
): AttachmentObject[] {
	const byHash = new Map<string, AttachmentOccurrence>();
	for (const item of attachments) {
		if (!byHash.has(item.sha256)) byHash.set(item.sha256, item);
	}
	return [...byHash.values()].map((item) =>
		buildAttachmentObject({
			sha256: item.sha256,
			bytes: item.bytes,
			mediaType: item.mediaType,
		}),
	);
}
