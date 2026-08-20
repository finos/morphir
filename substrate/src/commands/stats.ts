import { readFile } from "node:fs/promises";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root } from "mdast";

export interface LinkStats {
    external: number;
    local: number;
    anchors: number;
}

export interface StatsResult {
    wordCount: number;
    lineCount: number;
    tokenEstimate: number;
    links: LinkStats;
    sectionCount: number;
    maxHeaderDepth: number;
    avgHeaderDepth: number;
}

export async function statsFile(filePath: string): Promise<StatsResult> {
    const source = await readFile(filePath, "utf8");
    return computeStats(source);
}

export async function statsStdin(): Promise<StatsResult> {
    const chunks: Buffer[] = [];
    for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
    return computeStats(Buffer.concat(chunks).toString("utf8"));
}

export function computeStats(source: string): StatsResult {
    const root = unified().use(remarkParse).use(remarkGfm).parse(source) as Root;

    const lineCount = source.split("\n").length;
    const tokenEstimate = Math.ceil(source.length / 4);

    const text = extractText(root);
    const wordCount = text.trim() === "" ? 0 : text.trim().split(/\s+/).length;

    const links: LinkStats = { external: 0, local: 0, anchors: 0 };
    const depths: number[] = [];
    walkAst(root, links, depths);

    const sectionCount = depths.length;
    const maxHeaderDepth = sectionCount > 0 ? Math.max(...depths) : 0;
    const avgHeaderDepth =
        sectionCount > 0 ? depths.reduce((s, d) => s + d, 0) / sectionCount : 0;

    return { wordCount, lineCount, tokenEstimate, links, sectionCount, maxHeaderDepth, avgHeaderDepth };
}

export function formatStats(r: StatsResult): string {
    const lines: string[] = [];
    const row = (label: string, value: string): void => {
        lines.push(`${label.padEnd(22)}${value.padStart(8)}`);
    };

    row("Words:", r.wordCount.toLocaleString());
    row("Lines:", r.lineCount.toLocaleString());
    row("Tokens (est.):", r.tokenEstimate.toLocaleString());
    lines.push("");
    lines.push("Links:");
    row("  External:", r.links.external.toLocaleString());
    row("  Local:", r.links.local.toLocaleString());
    row("  Anchors:", r.links.anchors.toLocaleString());
    lines.push("");
    row("Sections:", r.sectionCount.toLocaleString());
    row("Max heading depth:", String(r.maxHeaderDepth));
    row("Avg heading depth:", r.avgHeaderDepth === 0 ? "0" : r.avgHeaderDepth.toFixed(1));

    return lines.join("\n");
}

function extractText(node: unknown): string {
    if (typeof node !== "object" || node === null) return "";
    const obj = node as Record<string, unknown>;
    if (obj["type"] === "code" || obj["type"] === "inlineCode") return "";
    if (obj["type"] === "text" && typeof obj["value"] === "string") {
        return (obj["value"] as string) + " ";
    }
    const children = obj["children"];
    if (Array.isArray(children)) return children.map(extractText).join("");
    return "";
}

function walkAst(node: unknown, links: LinkStats, depths: number[]): void {
    if (typeof node !== "object" || node === null) return;
    const obj = node as Record<string, unknown>;

    if (obj["type"] === "heading" && typeof obj["depth"] === "number") {
        depths.push(obj["depth"] as number);
    }

    if (
        (obj["type"] === "link" || obj["type"] === "definition") &&
        typeof obj["url"] === "string"
    ) {
        const url = obj["url"] as string;
        if (/^https?:\/\//.test(url) || url.startsWith("mailto:")) links.external++;
        else if (url.startsWith("#")) links.anchors++;
        else links.local++;
    }

    const children = obj["children"];
    if (Array.isArray(children)) {
        for (const child of children) walkAst(child, links, depths);
    }
}
