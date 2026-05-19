import {
    useCallback,
    useEffect,
    useRef,
    useState,
    type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import type { DocResponse } from "../../types";
import { isExternalHref, resolveLocalHref } from "../../router";
import { parseYaml, type YamlNode } from "./yaml";
import { SubstrateBlock, type SrcRef } from "./SubstrateBlock";
import { TreeSelect } from "./TreeSelect";
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
    /** File tree, rendered inside the documentation header dropdown. */
    readonly treeSlot: ReactNode;
    /** Path of the active doc, displayed in the tree dropdown button. */
    readonly activePath: string | null;
    /**
     * Lets the host close the tree dropdown after a selection. The host
     * stores the registered closer and invokes it from its tree-select
     * handler.
     */
    readonly onRegisterCloseTreeDropdown?: (close: () => void) => void;
}

export function Viewer({
    doc,
    loading,
    error,
    onNavigate,
    treeSlot,
    activePath,
    onRegisterCloseTreeDropdown,
}: ViewerProps): JSX.Element {
    const markdownRef = useRef<HTMLDivElement | null>(null);
    const interpRef = useRef<HTMLDivElement | null>(null);
    const [mounts, setMounts] = useState<readonly BlockMount[]>([]);
    const refsByBlockRef = useRef<SrcRef[][]>([]);

    // After the markdown HTML is injected, decorate external anchors and
    // extract substrate yaml blocks into the interpretation column.
    useEffect(() => {
        const root = markdownRef.current;
        const interp = interpRef.current;
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

        // Find every YAML code block whose root key is `substrate`. Remove
        // each from the prose entirely and append a placeholder element to
        // the interpretation column; render React content into the
        // placeholders via portals below.
        const found: BlockMount[] = [];
        if (interp) {
            interp.innerHTML = "";
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
                    interp.appendChild(host);
                    pre.remove();
                    found.push({ host, ast });
                } catch (err) {
                    console.warn("substrate block parse failed", err);
                }
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

    // Cross-element hover linkage between viz nodes (in the
    // interpretation column) and prose marks (in the documentation
    // column). Listens on both roots so a mouseover on either side
    // lights up the matching span on the other.
    useEffect(() => {
        const md = markdownRef.current;
        const interp = interpRef.current;
        if (!md && !interp) return;
        const roots: HTMLElement[] = [];
        if (md) roots.push(md);
        if (interp) roots.push(interp);

        let activeId: string | null = null;
        const setActive = (id: string | null): void => {
            if (id === activeId) return;
            if (activeId) {
                for (const r of roots) {
                    for (const el of r.querySelectorAll<HTMLElement>(
                        `[data-src-id="${cssEscape(activeId)}"]`,
                    )) {
                        el.classList.remove("substrate-src-active");
                    }
                }
            }
            activeId = id;
            if (id) {
                for (const r of roots) {
                    for (const el of r.querySelectorAll<HTMLElement>(
                        `[data-src-id="${cssEscape(id)}"]`,
                    )) {
                        el.classList.add("substrate-src-active");
                    }
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
        // Click a linked span on one side → scroll the matching span on
        // the other side into view. Picks the first match if many.
        const onClick = (e: Event): void => {
            const t = e.target as HTMLElement | null;
            if (!t) return;
            // Don't hijack clicks on anchors — link navigation wins.
            if (t.closest("a")) return;
            const hit = t.closest<HTMLElement>("[data-src-id]");
            if (!hit) return;
            const id = hit.dataset["srcId"];
            if (!id) return;
            for (const r of roots) {
                if (r.contains(hit)) continue;
                const target = r.querySelector<HTMLElement>(
                    `[data-src-id="${cssEscape(id)}"]`,
                );
                if (target) {
                    target.scrollIntoView({
                        behavior: "smooth",
                        block: "center",
                    });
                    break;
                }
            }
        };

        for (const r of roots) {
            r.addEventListener("mouseover", onOver);
            r.addEventListener("mouseout", onOut);
            r.addEventListener("click", onClick);
        }
        return () => {
            for (const r of roots) {
                r.removeEventListener("mouseover", onOver);
                r.removeEventListener("mouseout", onOut);
                r.removeEventListener("click", onClick);
            }
            setActive(null);
        };
    }, [doc, mounts]);

    const handleClick = useCallback(
        (e: React.MouseEvent<HTMLDivElement>) => {
            const anchor = (e.target as HTMLElement | null)?.closest("a");
            if (!anchor) return;
            const href = anchor.getAttribute("href");
            if (!href) return;

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
                return;
            }

            e.preventDefault();
            const { path, hash } = resolveLocalHref(href, doc?.path ?? null);
            onNavigate(path === "" ? null : path, hash ?? undefined);
        },
        [doc, onNavigate],
    );

    const docBody = renderDocBody({
        doc,
        loading,
        error,
        markdownRef,
        onClick: handleClick,
    });

    return (
        <>
            <section className={styles.column} aria-label="Documentation">
                <header className={styles.columnHeader}>
                    <span className={styles.columnTitle}>Documentation</span>
                </header>
                <div className={styles.docBody}>
                    <div className={styles.docScroll}>
                        <div className={styles.floatingBreadcrumb}>
                            <TreeSelect
                                activePath={activePath}
                                registerCloseOnSelect={
                                    onRegisterCloseTreeDropdown
                                }
                            >
                                {treeSlot}
                            </TreeSelect>
                        </div>
                        {docBody}
                    </div>
                </div>
            </section>
            <section className={styles.column} aria-label="Interpretation">
                <header className={styles.columnHeader}>
                    <span className={styles.columnTitle}>Interpretation</span>
                </header>
                <div className={styles.interpScroll}>
                    <div ref={interpRef} className={styles.interpInner} />
                    {doc && mounts.length === 0 && (
                        <div className={styles.empty}>
                            <div>
                                <div className={styles.emptyTitle}>
                                    No substrate definitions
                                </div>
                                <div>
                                    This document does not contain a substrate
                                    YAML block.
                                </div>
                            </div>
                        </div>
                    )}
                    {!doc && (
                        <div className={styles.empty}>
                            <div className={styles.emptyTitle}>
                                Nothing to interpret
                            </div>
                        </div>
                    )}
                </div>
            </section>
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
        </>
    );
}

interface RenderDocBodyArgs {
    readonly doc: DocResponse | null;
    readonly loading: boolean;
    readonly error: Error | null;
    readonly markdownRef: React.MutableRefObject<HTMLDivElement | null>;
    readonly onClick: (e: React.MouseEvent<HTMLDivElement>) => void;
}

function renderDocBody({
    doc,
    loading,
    error,
    markdownRef,
    onClick,
}: RenderDocBodyArgs): JSX.Element {
    if (error && !doc) {
        return (
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
        );
    }
    if (!doc && loading) {
        return (
            <div className={styles.inner}>
                <div className={styles.empty}>Loading…</div>
            </div>
        );
    }
    if (!doc) {
        return (
            <div className={styles.inner}>
                <div className={styles.empty}>
                    <div>
                        <div className={styles.emptyTitle}>Pick a document</div>
                        <div>Select a markdown file from the tree.</div>
                    </div>
                </div>
            </div>
        );
    }
    return (
        <div className={styles.inner}>
            <div
                ref={markdownRef}
                className={styles.markdown}
                onClick={onClick}
                // Markdown rendered server-side; HTML comes from the
                // substrate dev API. Treat the source as trusted —
                // this server only serves local files.
                dangerouslySetInnerHTML={{ __html: doc.html }}
            />
        </div>
    );
}

function cssEscape(value: string): string {
    if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
        return CSS.escape(value);
    }
    return value.replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function clearHighlights(root: HTMLElement): void {
    for (const badge of Array.from(
        root.querySelectorAll<HTMLElement>(".substrate-coverage-indicator"),
    )) {
        badge.remove();
    }
    for (const host of Array.from(
        root.querySelectorAll<HTMLElement>(".substrate-coverage-host"),
    )) {
        host.classList.remove("substrate-coverage-host");
        host.classList.remove("substrate-coverage-active");
    }
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
    const sorted = [...refs].sort((a, b) => b.text.length - a.text.length);
    const nodes = root.querySelectorAll<HTMLElement>(PROSE_SELECTOR);
    for (const node of Array.from(nodes)) {
        for (const ref of sorted) {
            highlightInElement(node, ref);
        }
    }
    decorateSectionCoverageIndicators(root);
}

function decorateSectionCoverageIndicators(root: HTMLElement): void {
    const headings = Array.from(
        root.querySelectorAll<HTMLElement>("h1, h2, h3, h4, h5, h6"),
    );
    for (const heading of headings) {
        const level = Number(heading.tagName.substring(1));
        const sectionEls: HTMLElement[] = [];
        let sibling = heading.nextElementSibling as HTMLElement | null;
        while (sibling) {
            const tag = sibling.tagName;
            if (/^H[1-6]$/.test(tag)) {
                const siblingLevel = Number(tag.substring(1));
                if (siblingLevel <= level) break;
            }
            sectionEls.push(sibling);
            sibling = sibling.nextElementSibling as HTMLElement | null;
        }

        let total = 0;
        let covered = 0;
        for (const el of sectionEls) {
            total += (el.textContent ?? "").length;
            for (const mark of Array.from(
                el.querySelectorAll<HTMLElement>("mark[data-substrate-src]"),
            )) {
                for (const child of Array.from(mark.childNodes)) {
                    if (child.nodeType === Node.TEXT_NODE) {
                        covered += (child as Text).data.length;
                    }
                }
            }
        }
        if (total === 0) continue;
        const pct = Math.min(100, Math.round((covered / total) * 100));

        const badge = document.createElement("span");
        badge.className = "substrate-coverage-indicator";
        badge.textContent = `${pct}%`;
        badge.title = `${pct}% of this section is linked to the visualisation`;
        badge.setAttribute("aria-hidden", "true");
        const setActive = (on: boolean): void => {
            heading.classList.toggle("substrate-coverage-active", on);
            for (const el of sectionEls) {
                el.classList.toggle("substrate-coverage-active", on);
            }
        };
        badge.addEventListener("mouseenter", () => setActive(true));
        badge.addEventListener("mouseleave", () => setActive(false));
        heading.classList.add("substrate-coverage-host");
        heading.appendChild(badge);
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
        if (
            parent instanceof HTMLElement &&
            parent.tagName === "MARK" &&
            parent.dataset["srcId"] === ref.id
        ) {
            continue;
        }
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
