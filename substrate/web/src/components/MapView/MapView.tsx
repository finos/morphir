import {
    useCallback,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import type { TreeNode } from "../../types";
import { fetchDoc } from "../../api/client";
import { isExternalHref, resolveLocalHref } from "../../router";
import styles from "./MapView.module.css";

export interface MapViewProps {
    readonly tree: TreeNode | null;
    readonly onNavigate: (path: string | null) => void;
}

type LinkIndex = ReadonlyMap<string, ReadonlySet<string>>;

export function MapView({ tree, onNavigate }: MapViewProps): JSX.Element {
    const [links, setLinks] = useState<LinkIndex>(new Map());
    const [loadingLinks, setLoadingLinks] = useState(false);

    useEffect(() => {
        if (!tree) return;
        let cancelled = false;
        const docs = collectDocs(tree);
        setLoadingLinks(true);
        Promise.all(
            docs.map((p) =>
                fetchDoc(p)
                    .then((r) => [p, extractLinks(r.html, p)] as const)
                    .catch(() => [p, new Set<string>()] as const),
            ),
        ).then((entries) => {
            if (cancelled) return;
            const map = new Map<string, Set<string>>();
            for (const [p, s] of entries) map.set(p, s);
            setLinks(map);
            setLoadingLinks(false);
        });
        return () => {
            cancelled = true;
        };
    }, [tree]);

    // Pan + zoom over the inner canvas.
    const [zoom, setZoom] = useState(1);
    const [pan, setPan] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
    const viewportRef = useRef<HTMLDivElement | null>(null);
    const dragRef = useRef<{
        startX: number;
        startY: number;
        panX: number;
        panY: number;
    } | null>(null);

    const onWheel = useCallback(
        (e: React.WheelEvent<HTMLDivElement>) => {
            if (!e.ctrlKey && !e.metaKey && Math.abs(e.deltaX) < 0.01) {
                // Allow normal scroll when no modifier and no horizontal hint.
                // But we always zoom — treat the canvas as a map.
            }
            e.preventDefault();
            const vp = viewportRef.current;
            if (!vp) return;
            const rect = vp.getBoundingClientRect();
            const px = e.clientX - rect.left;
            const py = e.clientY - rect.top;
            const factor = Math.exp(-e.deltaY * 0.0015);
            const nextZoom = Math.min(4, Math.max(0.1, zoom * factor));
            // Keep the point under the cursor stationary.
            const k = nextZoom / zoom;
            setPan({
                x: px - k * (px - pan.x),
                y: py - k * (py - pan.y),
            });
            setZoom(nextZoom);
        },
        [pan.x, pan.y, zoom],
    );

    const onMouseDown = useCallback(
        (e: React.MouseEvent<HTMLDivElement>) => {
            if (e.button !== 0) return;
            const target = e.target as HTMLElement | null;
            // Don't start a pan when clicking on a doc card.
            if (target?.closest(`.${styles.docCard}`)) return;
            dragRef.current = {
                startX: e.clientX,
                startY: e.clientY,
                panX: pan.x,
                panY: pan.y,
            };
            (e.currentTarget as HTMLDivElement).style.cursor = "grabbing";
        },
        [pan.x, pan.y],
    );
    useEffect(() => {
        const onMove = (e: MouseEvent): void => {
            const d = dragRef.current;
            if (!d) return;
            setPan({
                x: d.panX + (e.clientX - d.startX),
                y: d.panY + (e.clientY - d.startY),
            });
        };
        const onUp = (): void => {
            if (!dragRef.current) return;
            dragRef.current = null;
            const vp = viewportRef.current;
            if (vp) vp.style.cursor = "grab";
        };
        window.addEventListener("mousemove", onMove);
        window.addEventListener("mouseup", onUp);
        return () => {
            window.removeEventListener("mousemove", onMove);
            window.removeEventListener("mouseup", onUp);
        };
    }, []);

    const resetView = useCallback(() => {
        setZoom(1);
        setPan({ x: 24, y: 24 });
    }, []);

    useEffect(() => {
        // Initial offset so the root box isn't flush against the corner.
        setPan({ x: 24, y: 24 });
    }, [tree]);

    if (!tree) {
        return <div className={styles.empty}>Loading tree…</div>;
    }

    return (
        <div className={styles.root}>
            <div className={styles.toolbar}>
                <button
                    type="button"
                    className={styles.toolBtn}
                    onClick={() => setZoom((z) => Math.min(4, z * 1.2))}
                >
                    +
                </button>
                <button
                    type="button"
                    className={styles.toolBtn}
                    onClick={() => setZoom((z) => Math.max(0.1, z / 1.2))}
                >
                    −
                </button>
                <button
                    type="button"
                    className={styles.toolBtn}
                    onClick={resetView}
                >
                    reset
                </button>
                <span className={styles.zoomReadout}>
                    {Math.round(zoom * 100)}%
                    {loadingLinks ? " · indexing links…" : ""}
                </span>
            </div>
            <div
                ref={viewportRef}
                className={styles.viewport}
                onWheel={onWheel}
                onMouseDown={onMouseDown}
            >
                <div
                    className={styles.canvas}
                    style={{
                        transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
                    }}
                >
                    <FolderBox
                        node={tree}
                        links={links}
                        onNavigate={onNavigate}
                        isRoot
                    />
                </div>
            </div>
        </div>
    );
}

interface FolderBoxProps {
    readonly node: TreeNode;
    readonly links: LinkIndex;
    readonly onNavigate: (path: string | null) => void;
    readonly isRoot?: boolean;
}

function FolderBox({
    node,
    links,
    onNavigate,
    isRoot,
}: FolderBoxProps): JSX.Element {
    const children = node.children ?? [];

    const { layers, edges } = useMemo(
        () => layoutFolder(node, links),
        [node, links],
    );

    const layersRef = useRef<HTMLDivElement | null>(null);
    const childRefs = useRef<Map<string, HTMLElement>>(new Map());
    const [arrows, setArrows] = useState<readonly ArrowGeom[]>([]);
    const [svgSize, setSvgSize] = useState<{ w: number; h: number }>({
        w: 0,
        h: 0,
    });

    const recomputeArrows = useCallback(() => {
        const container = layersRef.current;
        if (!container) return;
        const cbox = container.getBoundingClientRect();
        const rects = new Map<string, DOMRect>();
        for (const [path, el] of childRefs.current) {
            rects.set(path, el.getBoundingClientRect());
        }
        const out: ArrowGeom[] = [];
        for (const [src, targets] of edges) {
            const a = rects.get(src);
            if (!a) continue;
            for (const tgt of targets) {
                const b = rects.get(tgt);
                if (!b) continue;
                // Source: right-center; target: left-center, in container space.
                const x1 = a.right - cbox.left;
                const y1 = a.top + a.height / 2 - cbox.top;
                const x2 = b.left - cbox.left;
                const y2 = b.top + b.height / 2 - cbox.top;
                out.push({ x1, y1, x2, y2, key: `${src}→${tgt}` });
            }
        }
        setArrows(out);
        setSvgSize({ w: cbox.width, h: cbox.height });
    }, [edges]);

    useLayoutEffect(() => {
        recomputeArrows();
    }, [recomputeArrows, layers, links]);

    useEffect(() => {
        const container = layersRef.current;
        if (!container || typeof ResizeObserver === "undefined") return;
        const ro = new ResizeObserver(() => recomputeArrows());
        ro.observe(container);
        for (const el of childRefs.current.values()) ro.observe(el);
        return () => ro.disconnect();
    }, [recomputeArrows, layers]);

    const setChildRef = (path: string) => (el: HTMLElement | null): void => {
        if (el) childRefs.current.set(path, el);
        else childRefs.current.delete(path);
    };

    const folderClass = isRoot
        ? `${styles.folder} ${styles.folderRoot}`
        : styles.folder;

    return (
        <div className={folderClass}>
            <div className={styles.folderHeader}>
                <span className={styles.folderIcon}>▸</span>
                <span className={styles.folderName}>{node.name || "/"}</span>
                <span className={styles.folderMeta}>
                    {children.length} item{children.length === 1 ? "" : "s"}
                </span>
            </div>
            {children.length === 0 ? (
                <div className={styles.folderEmpty}>empty</div>
            ) : (
                <div ref={layersRef} className={styles.layers}>
                    {layers.map((layer, i) => (
                        <div key={i} className={styles.layer}>
                            {layer.map((path) => {
                                const c = children.find(
                                    (x) => x.path === path,
                                );
                                if (!c) return null;
                                if (c.type === "dir") {
                                    return (
                                        <div
                                            key={c.path}
                                            ref={setChildRef(c.path)}
                                            className={styles.childSlot}
                                        >
                                            <FolderBox
                                                node={c}
                                                links={links}
                                                onNavigate={onNavigate}
                                            />
                                        </div>
                                    );
                                }
                                return (
                                    <button
                                        key={c.path}
                                        ref={setChildRef(c.path)}
                                        type="button"
                                        className={styles.docCard}
                                        title={c.path}
                                        onClick={() => onNavigate(c.path)}
                                    >
                                        <span className={styles.docIcon}>
                                            ¶
                                        </span>
                                        <span className={styles.docName}>
                                            {c.name}
                                        </span>
                                    </button>
                                );
                            })}
                        </div>
                    ))}
                    <svg
                        className={styles.arrows}
                        width={svgSize.w}
                        height={svgSize.h}
                        viewBox={`0 0 ${svgSize.w} ${svgSize.h}`}
                    >
                        <defs>
                            <marker
                                id={`arrowhead-${node.path || "root"}`}
                                viewBox="0 0 10 10"
                                refX="9"
                                refY="5"
                                markerWidth="6"
                                markerHeight="6"
                                orient="auto-start-reverse"
                            >
                                <path
                                    d="M 0 0 L 10 5 L 0 10 z"
                                    className={styles.arrowHead}
                                />
                            </marker>
                        </defs>
                        {arrows.map((a) => {
                            const dx = a.x2 - a.x1;
                            const c1x = a.x1 + dx * 0.4;
                            const c2x = a.x2 - dx * 0.4;
                            return (
                                <path
                                    key={a.key}
                                    className={styles.arrow}
                                    d={`M ${a.x1} ${a.y1} C ${c1x} ${a.y1}, ${c2x} ${a.y2}, ${a.x2} ${a.y2}`}
                                    markerEnd={`url(#arrowhead-${node.path || "root"})`}
                                />
                            );
                        })}
                    </svg>
                </div>
            )}
        </div>
    );
}

interface ArrowGeom {
    readonly x1: number;
    readonly y1: number;
    readonly x2: number;
    readonly y2: number;
    readonly key: string;
}

/* -------------------------- layout & link logic -------------------------- */

function collectDocs(node: TreeNode): string[] {
    const out: string[] = [];
    const walk = (n: TreeNode): void => {
        if (n.type === "file" && n.name.toLowerCase().endsWith(".md")) {
            out.push(n.path);
        }
        for (const c of n.children ?? []) walk(c);
    };
    walk(node);
    return out;
}

function extractLinks(html: string, docPath: string): Set<string> {
    const out = new Set<string>();
    if (typeof DOMParser === "undefined") return out;
    const dom = new DOMParser().parseFromString(html, "text/html");
    for (const a of Array.from(dom.querySelectorAll("a[href]"))) {
        const href = a.getAttribute("href");
        if (!href || isExternalHref(href) || href.startsWith("#")) continue;
        const { path } = resolveLocalHref(href, docPath);
        if (path) out.add(path);
    }
    return out;
}

/**
 * Given a folder, compute (a) the edge map between its direct children
 * (projecting links from any descendant doc through its top-level
 * ancestor) and (b) a longest-path layering of those children.
 */
function layoutFolder(
    node: TreeNode,
    links: LinkIndex,
): {
    readonly layers: readonly (readonly string[])[];
    readonly edges: ReadonlyMap<string, ReadonlySet<string>>;
} {
    const children = node.children ?? [];
    const childPaths = children.map((c) => c.path);

    // Map every descendant path → which direct child of `node` it belongs to.
    const ownerOfDescendant = new Map<string, string>();
    for (const child of children) {
        const stack: TreeNode[] = [child];
        while (stack.length > 0) {
            const cur = stack.pop()!;
            ownerOfDescendant.set(cur.path, child.path);
            for (const g of cur.children ?? []) stack.push(g);
        }
    }

    const edges = new Map<string, Set<string>>();
    for (const p of childPaths) edges.set(p, new Set());

    for (const [srcDoc, targets] of links) {
        const srcOwner = ownerOfDescendant.get(srcDoc);
        if (!srcOwner) continue;
        for (const tgt of targets) {
            const tgtOwner = ownerOfDescendant.get(tgt);
            if (!tgtOwner || tgtOwner === srcOwner) continue;
            edges.get(srcOwner)!.add(tgtOwner);
        }
    }

    const layers = layerize(childPaths, edges);
    return { layers, edges };
}

function layerize(
    nodes: readonly string[],
    edges: ReadonlyMap<string, ReadonlySet<string>>,
): string[][] {
    const indeg = new Map<string, number>();
    for (const n of nodes) indeg.set(n, 0);
    for (const [src, targets] of edges) {
        if (!indeg.has(src)) continue;
        for (const t of targets) {
            if (indeg.has(t)) indeg.set(t, (indeg.get(t) ?? 0) + 1);
        }
    }
    const remaining = new Set(nodes);
    const layers: string[][] = [];
    while (remaining.size > 0) {
        const layer: string[] = [];
        for (const n of remaining) {
            if ((indeg.get(n) ?? 0) === 0) layer.push(n);
        }
        if (layer.length === 0) {
            // Cycle — put everything left in one final layer.
            layer.push(...remaining);
        }
        layer.sort();
        layers.push(layer);
        for (const n of layer) {
            remaining.delete(n);
            const out = edges.get(n);
            if (!out) continue;
            for (const t of out) {
                if (remaining.has(t)) {
                    indeg.set(t, (indeg.get(t) ?? 1) - 1);
                }
            }
        }
    }
    return layers;
}
