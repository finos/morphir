import { useCallback, useEffect, useRef } from "react";
import type { DocResponse } from "../../types";
import { isExternalHref, resolveLocalHref } from "../../router";
import { parseYaml } from "./yaml";
import { renderSubstrateBlock, type SrcRef } from "./substrateBlock";
import styles from "./Viewer.module.css";

export interface ViewerProps {
    readonly doc: DocResponse | null;
    readonly loading: boolean;
    readonly error: Error | null;
    /**
     * Called when the user clicks a local link inside the rendered
     * markdown. The viewer has already prevented the default browser
     * navigation; the host decides how to update the URL and state.
     */
    readonly onNavigate: (path: string | null, hash?: string) => void;
}

export function Viewer({
    doc,
    loading,
    error,
    onNavigate,
}: ViewerProps): JSX.Element {
    const markdownRef = useRef<HTMLDivElement | null>(null);

    // After the markdown HTML is injected, decorate external anchors so
    // they open in a new tab — we want this even if the click reaches the
    // browser's default handler (e.g. middle-click, keyboard activation).
    useEffect(() => {
        const root = markdownRef.current;
        if (!root || !doc) return;
        for (const a of root.querySelectorAll<HTMLAnchorElement>("a[href]")) {
            const href = a.getAttribute("href") ?? "";
            if (isExternalHref(href)) {
                a.setAttribute("target", "_blank");
                a.setAttribute("rel", "noopener noreferrer");
            }
        }

        // Find every YAML code block whose root key is `substrate` and
        // swap the original `<pre>` for a rich visualisation. Collect
        // the `src` references the renderer surfaced so we can
        // highlight matching prose elsewhere in the document.
        const refs: SrcRef[] = [];
        const codes = root.querySelectorAll<HTMLElement>(
            "pre > code.language-yaml",
        );
        for (const code of Array.from(codes)) {
            const pre = code.parentElement;
            if (!pre) continue;
            const text = code.textContent ?? "";
            if (!/^\s*substrate\s*:/m.test(text)) continue;
            try {
                const ast = parseYaml(text);
                const { element, refs: blockRefs } = renderSubstrateBlock(ast);
                pre.replaceWith(element);
                refs.push(...blockRefs);
            } catch (err) {
                console.warn("substrate block parse failed", err);
            }
        }

        if (refs.length > 0) highlightSrcReferences(root, refs);
    }, [doc]);

    const handleClick = useCallback(
        (e: React.MouseEvent<HTMLDivElement>) => {
            const anchor = (e.target as HTMLElement | null)?.closest("a");
            if (!anchor) return;
            const href = anchor.getAttribute("href");
            if (!href) return;

            // Let the browser handle modified clicks (new tab/window),
            // non-primary buttons, and external links.
            if (
                e.defaultPrevented ||
                e.button !== 0 ||
                e.metaKey ||
                e.ctrlKey ||
                e.shiftKey ||
                e.altKey
            ) {
                return;
            }
            if (isExternalHref(href)) {
                // The useEffect above already added target=_blank; the
                // browser's default action will open it in a new tab.
                return;
            }

            e.preventDefault();
            const { path, hash } = resolveLocalHref(href, doc?.path ?? null);
            onNavigate(path === "" ? null : path, hash ?? undefined);
        },
        [doc, onNavigate],
    );

    if (error && !doc) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>
                        <div>
                            <div className={styles.emptyTitle}>
                                Couldn't load that file
                            </div>
                            <div>{error.message}</div>
                        </div>
                    </div>
                </div>
            </main>
        );
    }

    if (!doc && loading) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>Loading…</div>
                </div>
            </main>
        );
    }

    if (!doc) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>
                        <div>
                            <div className={styles.emptyTitle}>
                                Pick a document
                            </div>
                            <div>
                                Select a markdown file from the tree on the
                                left.
                            </div>
                        </div>
                    </div>
                </div>
            </main>
        );
    }

    return (
        <main className={styles.viewer}>
            <div className={styles.inner}>
                <div className={styles.breadcrumb}>
                    {doc.path.split("/").join(" / ")}
                </div>
                <div
                    ref={markdownRef}
                    className={styles.markdown}
                    onClick={handleClick}
                    // Markdown rendered server-side; HTML comes from the
                    // substrate dev API. Treat the source as trusted —
                    // this server only serves local files.
                    dangerouslySetInnerHTML={{ __html: doc.html }}
                />
            </div>
        </main>
    );
}

const PROSE_SELECTOR = "p, li, blockquote, h1, h2, h3, h4, h5, h6";

function highlightSrcReferences(
    root: HTMLElement,
    refs: readonly SrcRef[],
): void {
    // Sort by length descending so longer phrases match before shorter
    // sub-phrases would consume them.
    const sorted = [...refs].sort((a, b) => b.text.length - a.text.length);
    const nodes = root.querySelectorAll<HTMLElement>(PROSE_SELECTOR);
    for (const node of Array.from(nodes)) {
        for (const ref of sorted) {
            highlightInElement(node, ref);
        }
    }
}

function highlightInElement(node: HTMLElement, ref: SrcRef): void {
    if (!ref.text || ref.text.length < 3) return;
    const needle = ref.text.toLowerCase();
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    const textNodes: Text[] = [];
    let n: Node | null = walker.nextNode();
    while (n) {
        textNodes.push(n as Text);
        n = walker.nextNode();
    }
    for (const t of textNodes) {
        const parent = t.parentElement;
        if (!parent) continue;
        // Don't re-wrap inside an existing mark.
        if (parent.closest("mark[data-substrate-src]")) continue;
        const hay = t.data.toLowerCase();
        const idx = hay.indexOf(needle);
        if (idx < 0) continue;
        const before = t.data.slice(0, idx);
        const match = t.data.slice(idx, idx + ref.text.length);
        const after = t.data.slice(idx + ref.text.length);
        const mark = document.createElement("mark");
        mark.dataset.substrateSrc = "true";
        mark.style.backgroundColor = `color-mix(in srgb, ${ref.color} 22%, transparent)`;
        mark.style.borderBottom = `2px solid ${ref.color}`;
        mark.style.padding = "0 2px";
        mark.style.borderRadius = "2px";
        mark.textContent = match;
        const frag = document.createDocumentFragment();
        if (before) frag.appendChild(document.createTextNode(before));
        frag.appendChild(mark);
        if (after) frag.appendChild(document.createTextNode(after));
        t.replaceWith(frag);
    }
}
