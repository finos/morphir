import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { DocResponse } from "../../types";
import { isExternalHref, resolveLocalHref } from "../../router";
import { parseYaml, type YamlNode } from "./yaml";
import { SubstrateBlock, type SrcRef } from "./SubstrateBlock";
import styles from "./Viewer.module.css";

interface BlockMount {
    readonly host: HTMLElement;
    readonly ast: YamlNode;
}

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
    const [mounts, setMounts] = useState<readonly BlockMount[]>([]);
    const refsByBlockRef = useRef<SrcRef[][]>([]);

    // After the markdown HTML is injected, decorate external anchors so
    // they open in a new tab — we want this even if the click reaches the
    // browser's default handler (e.g. middle-click, keyboard activation).
    useEffect(() => {
        const root = markdownRef.current;
        if (!root || !doc) {
            setMounts([]);
            return;
        }
        for (const a of root.querySelectorAll<HTMLAnchorElement>("a[href]")) {
            const href = a.getAttribute("href") ?? "";
            if (isExternalHref(href)) {
                a.setAttribute("target", "_blank");
                a.setAttribute("rel", "noopener noreferrer");
            }
        }

        // Find every YAML code block whose root key is `substrate` and
        // swap the original `<pre>` for a placeholder div we'll render
        // a React-based visualisation into via a portal.
        const found: BlockMount[] = [];
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
                const host = document.createElement("div");
                host.className = "substrate-mount";
                pre.replaceWith(host);
                found.push({ host, ast });
            } catch (err) {
                console.warn("substrate block parse failed", err);
            }
        }
        refsByBlockRef.current = found.map(() => []);
        setMounts(found);
    }, [doc]);

    // Re-run prose highlighting whenever the collected src refs change.
    const onRefsForBlock = useCallback(
        (index: number, refs: readonly SrcRef[]) => {
            refsByBlockRef.current[index] = [...refs];
            const root = markdownRef.current;
            if (!root) return;
            clearHighlights(root);
            const all = refsByBlockRef.current.flat();
            if (all.length > 0) highlightSrcReferences(root, all);
        },
        [],
    );

    // Cross-element hover linkage between viz nodes and prose marks.
    // Listens on the markdown root (which contains both, since the
    // substrate visualisations live inside the root via portals).
    useEffect(() => {
        const root = markdownRef.current;
        if (!root) return;
        let activeId: string | null = null;
        const setActive = (id: string | null): void => {
            if (id === activeId) return;
            if (activeId) {
                for (const el of root.querySelectorAll<HTMLElement>(
                    `[data-src-id="${cssEscape(activeId)}"]`,
                )) {
                    el.classList.remove("substrate-src-active");
                }
            }
            activeId = id;
            if (id) {
                for (const el of root.querySelectorAll<HTMLElement>(
                    `[data-src-id="${cssEscape(id)}"]`,
                )) {
                    el.classList.add("substrate-src-active");
                }
            }
        };
        const onOver = (e: Event): void => {
            const t = e.target as HTMLElement | null;
            if (!t) return;
            const hit = t.closest<HTMLElement>("[data-src-id]");
            setActive(hit?.dataset["srcId"] ?? null);
        };
        const onOut = (e: Event): void => {
            const t = e.target as HTMLElement | null;
            const rel = (e as MouseEvent).relatedTarget as HTMLElement | null;
            if (!t) return;
            const fromHit = t.closest<HTMLElement>("[data-src-id]");
            if (!fromHit) return;
            const toHit = rel?.closest<HTMLElement>("[data-src-id]") ?? null;
            if (toHit && toHit.dataset["srcId"] === fromHit.dataset["srcId"]) {
                return;
            }
            setActive(toHit?.dataset["srcId"] ?? null);
        };
        root.addEventListener("mouseover", onOver);
        root.addEventListener("mouseout", onOut);
        return () => {
            root.removeEventListener("mouseover", onOver);
            root.removeEventListener("mouseout", onOut);
            setActive(null);
        };
    }, [doc, mounts]);

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
                {mounts.map((m, i) =>
                    createPortal(
                        <SubstrateBlock
                            blockId={`b${i}`}
                            ast={m.ast}
                            onRefs={(refs) => onRefsForBlock(i, refs)}
                        />,
                        m.host,
                        `substrate-mount-${i}`,
                    ),
                )}
            </div>
        </main>
    );
}

function cssEscape(value: string): string {
    if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
        return CSS.escape(value);
    }
    return value.replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function clearHighlights(root: HTMLElement): void {
    for (const mark of Array.from(
        root.querySelectorAll<HTMLElement>("mark[data-substrate-src]"),
    )) {
        const parent = mark.parentNode;
        if (!parent) continue;
        parent.replaceChild(
            document.createTextNode(mark.textContent ?? ""),
            mark,
        );
        parent.normalize();
    }
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
        if (parent.closest("mark[data-substrate-src]")) continue;
        const hay = t.data.toLowerCase();
        const idx = hay.indexOf(needle);
        if (idx < 0) continue;
        const before = t.data.slice(0, idx);
        const match = t.data.slice(idx, idx + ref.text.length);
        const after = t.data.slice(idx + ref.text.length);
        const mark = document.createElement("mark");
        mark.dataset.substrateSrc = "true";
        mark.dataset.srcId = ref.id;
        mark.setAttribute("data-src-id", ref.id);
        mark.textContent = match;
        const frag = document.createDocumentFragment();
        if (before) frag.appendChild(document.createTextNode(before));
        frag.appendChild(mark);
        if (after) frag.appendChild(document.createTextNode(after));
        t.replaceWith(frag);
    }
}
