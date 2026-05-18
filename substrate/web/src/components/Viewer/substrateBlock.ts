/**
 * Imperative renderer for a parsed substrate YAML block. The viewer
 * calls this to replace the original `<pre>` element with a richer
 * tree visualisation; the same call returns the `src` → colour map so
 * the viewer can highlight the matching prose elsewhere in the doc.
 */
import type { YamlNode } from "./yaml.js";
import rawStyles from "./SubstrateBlock.module.css";

const styles: Record<string, string> = rawStyles;
const cls = (key: string): string => styles[key] ?? "";

export interface SrcRef {
    readonly color: string;
    readonly text: string;
}

const HUES = [200, 28, 145, 280, 0, 50, 320, 175];

const colorFor = (index: number): string => {
    const hue = HUES[index % HUES.length] ?? 200;
    return `hsl(${hue} 70% 45%)`;
};

const formatScalar = (v: string | number | boolean | null): string => {
    if (v === null) return "∅";
    return String(v);
};

interface Ctx {
    readonly refs: SrcRef[];
}

const findSrc = (node: YamlNode): string | null => {
    if (node.kind !== "mapping") return null;
    for (const [k, v] of node.entries) {
        if (k === "src" && v.kind === "scalar" && typeof v.value === "string") {
            return v.value;
        }
    }
    return null;
};

const renderNode = (
    node: YamlNode,
    ctx: Ctx,
    keyLabel: string | null,
): HTMLElement => {
    if (node.kind === "scalar") {
        const el = document.createElement("span");
        el.className = cls("scalar");
        const v = node.value;
        if (typeof v === "number") el.classList.add(cls("scalarNumber"));
        else if (typeof v === "boolean") el.classList.add(cls("scalarBool"));
        else if (v === null) el.classList.add(cls("scalarNull"));
        el.textContent = formatScalar(v);
        return wrapWithKey(keyLabel, el, null);
    }

    if (node.kind === "sequence") {
        const list = document.createElement("ul");
        list.className = cls("sequence");
        for (const item of node.items) {
            const li = document.createElement("li");
            li.className = cls("sequenceItem");
            li.appendChild(renderNode(item, ctx, null));
            list.appendChild(li);
        }
        return wrapWithKey(keyLabel, list, null);
    }

    const src = findSrc(node);
    let srcColor: string | null = null;
    if (src) {
        srcColor = colorFor(ctx.refs.length);
        ctx.refs.push({ color: srcColor, text: src });
    }

    const card = document.createElement("div");
    card.className = cls("mapping");
    if (srcColor) {
        card.classList.add(cls("mappingWithSrc"));
        card.style.setProperty("--src-color", srcColor);
    }

    for (const [k, v] of node.entries) {
        if (k === "src") continue;
        const row = document.createElement("div");
        row.className = cls("row");
        row.appendChild(renderNode(v, ctx, k));
        card.appendChild(row);
    }

    if (src && srcColor) {
        const badge = document.createElement("div");
        badge.className = cls("srcBadge");
        badge.style.backgroundColor = srcColor;
        badge.textContent = src;
        card.appendChild(badge);
    }

    return wrapWithKey(keyLabel, card, srcColor);
};

const wrapWithKey = (
    keyLabel: string | null,
    inner: HTMLElement,
    accent: string | null,
): HTMLElement => {
    if (!keyLabel) return inner;
    const wrap = document.createElement("div");
    wrap.className = cls("keyed");
    const key = document.createElement("div");
    key.className = cls("key");
    if (accent) key.style.color = accent;
    key.textContent = keyLabel;
    wrap.appendChild(key);
    const valueWrap = document.createElement("div");
    valueWrap.className = cls("value");
    valueWrap.appendChild(inner);
    wrap.appendChild(valueWrap);
    return wrap;
};

export interface RenderResult {
    readonly element: HTMLElement;
    readonly refs: readonly SrcRef[];
}

export const renderSubstrateBlock = (root: YamlNode): RenderResult => {
    const container = document.createElement("div");
    container.className = cls("block");

    const header = document.createElement("div");
    header.className = cls("header");
    const tag = document.createElement("span");
    tag.className = cls("tag");
    tag.textContent = "substrate";
    header.appendChild(tag);
    const subtitle = document.createElement("span");
    subtitle.className = cls("subtitle");
    subtitle.textContent = "executable specification";
    header.appendChild(subtitle);
    container.appendChild(header);

    const ctx: Ctx = { refs: [] };

    if (root.kind === "mapping") {
        const sub = root.entries.find(([k]) => k === "substrate");
        const body = sub ? sub[1] : root;
        container.appendChild(renderNode(body, ctx, null));
    } else {
        container.appendChild(renderNode(root, ctx, null));
    }

    return { element: container, refs: ctx.refs };
};
