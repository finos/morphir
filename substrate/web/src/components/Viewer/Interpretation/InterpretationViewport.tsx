/**
 * Outer pan-and-zoom container for the interpretation visualisation.
 * Everything inside the viewport — including the deeply-nested
 * fixed-slot NodeSlot tree — sits on an inner canvas that we
 * translate and scale to implement pan, wheel-zoom, and the
 * click-to-zoom behaviour that brings a clicked slot back toward its
 * natural size.
 *
 * The viewport publishes the current zoom level through
 * InterpretationContext as `effectiveScale`, so NodeSlots further
 * down the tree can multiply it into their own slot scale and decide
 * whether content is still legible or should be replaced with a
 * placeholder.
 */
import {
    useCallback,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
    type JSX,
    type ReactNode,
} from "react";
import {
    InterpretationContext,
    type ZoomTarget,
} from "./context";
import styles from "./InterpretationViewport.module.css";

export interface InterpretationViewportProps {
    readonly children: ReactNode;
}

interface View {
    readonly zoom: number;
    readonly x: number;
    readonly y: number;
}

const MIN_ZOOM = 0.05;
const ZOOM_ANIM_MS = 320;

export function InterpretationViewport({
    children,
}: InterpretationViewportProps): JSX.Element {
    const viewportRef = useRef<HTMLDivElement | null>(null);
    const canvasRef = useRef<HTMLDivElement | null>(null);

    const [view, setView] = useState<View>({ zoom: 1, x: 16, y: 16 });
    const [animating, setAnimating] = useState(false);
    const dragRef = useRef<{
        sx: number;
        sy: number;
        x: number;
        y: number;
    } | null>(null);

    // Wheel = anchored zoom around the cursor. Keeps the point under
    // the mouse stationary as the inner canvas scales.
    const onWheel = useCallback(
        (e: React.WheelEvent<HTMLDivElement>) => {
            e.preventDefault();
            const vp = viewportRef.current;
            if (!vp) return;
            const rect = vp.getBoundingClientRect();
            const px = e.clientX - rect.left;
            const py = e.clientY - rect.top;
            const factor = Math.exp(-e.deltaY * 0.0015);
            setView((cur) => {
                const next = Math.max(MIN_ZOOM, cur.zoom * factor);
                const k = next / cur.zoom;
                return {
                    zoom: next,
                    x: px - k * (px - cur.x),
                    y: py - k * (py - cur.y),
                };
            });
        },
        [],
    );

    const onMouseDown = useCallback(
        (e: React.MouseEvent<HTMLDivElement>) => {
            if (e.button !== 0) return;
            const t = e.target as HTMLElement | null;
            // Let interactive children handle their own clicks.
            if (t?.closest("a, button, [data-slot-kind]")) return;
            dragRef.current = {
                sx: e.clientX,
                sy: e.clientY,
                x: view.x,
                y: view.y,
            };
            (e.currentTarget as HTMLDivElement).style.cursor = "grabbing";
        },
        [view.x, view.y],
    );

    useEffect(() => {
        const onMove = (e: MouseEvent): void => {
            const d = dragRef.current;
            if (!d) return;
            setView((cur) => ({
                zoom: cur.zoom,
                x: d.x + (e.clientX - d.sx),
                y: d.y + (e.clientY - d.sy),
            }));
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

    // Click-to-zoom: animate the viewport so the clicked slot
    // (measured in its current scaled position on screen) fills most
    // of the viewport, effectively undoing the compounded ancestor
    // scales and returning the slot to ~natural size.
    const requestZoomTo = useCallback((target: ZoomTarget): void => {
        const vp = viewportRef.current;
        const canvas = canvasRef.current;
        if (!vp || !canvas) return;
        const vpRect = vp.getBoundingClientRect();
        const tRect = target.element.getBoundingClientRect();
        if (tRect.width <= 0 || tRect.height <= 0) return;

        // Position of the slot in canvas-local coords, accounting for
        // the current view transform.
        const canvasRect = canvas.getBoundingClientRect();
        const localX = (tRect.left - canvasRect.left) / view.zoom;
        const localY = (tRect.top - canvasRect.top) / view.zoom;
        const localW = tRect.width / view.zoom;
        const localH = tRect.height / view.zoom;

        const margin = 0.9;
        const nextZoom = Math.max(
            MIN_ZOOM,
            Math.min(
                (vpRect.width * margin) / localW,
                (vpRect.height * margin) / localH,
            ),
        );

        // Center the slot in the viewport at the new zoom.
        const cx = vpRect.width / 2;
        const cy = vpRect.height / 2;
        const nextX = cx - (localX + localW / 2) * nextZoom;
        const nextY = cy - (localY + localH / 2) * nextZoom;

        setAnimating(true);
        setView({ zoom: nextZoom, x: nextX, y: nextY });
        window.setTimeout(() => setAnimating(false), ZOOM_ANIM_MS);
    }, [view.zoom]);

    const reset = useCallback(() => {
        setAnimating(true);
        setView({ zoom: 1, x: 16, y: 16 });
        window.setTimeout(() => setAnimating(false), ZOOM_ANIM_MS);
    }, []);

    const ctxValue = useMemo(
        () => ({
            effectiveScale: view.zoom,
            requestZoomTo,
        }),
        [view.zoom, requestZoomTo],
    );

    // Touch/keyboard pan: arrow keys nudge the canvas if focused.
    const onKeyDown = (e: React.KeyboardEvent<HTMLDivElement>): void => {
        const step = 40;
        if (e.key === "ArrowLeft")
            setView((v) => ({ ...v, x: v.x + step }));
        else if (e.key === "ArrowRight")
            setView((v) => ({ ...v, x: v.x - step }));
        else if (e.key === "ArrowUp")
            setView((v) => ({ ...v, y: v.y + step }));
        else if (e.key === "ArrowDown")
            setView((v) => ({ ...v, y: v.y - step }));
        else if (e.key === "0") reset();
        else return;
        e.preventDefault();
    };

    // After mount, on first paint, no extra layout to do — but recompute
    // canvas size on resize so reset stays sensible.
    useLayoutEffect(() => {
        // no-op: kept for parallelism with measurement systems
    }, []);

    return (
        <InterpretationContext.Provider value={ctxValue}>
            <div className={styles.shell}>
                <div className={styles.toolbar}>
                    <button
                        type="button"
                        className={styles.toolBtn}
                        onClick={() =>
                            setView((v) => ({
                                ...v,
                                zoom: v.zoom * 1.2,
                            }))
                        }
                    >
                        +
                    </button>
                    <button
                        type="button"
                        className={styles.toolBtn}
                        onClick={() =>
                            setView((v) => ({
                                ...v,
                                zoom: Math.max(MIN_ZOOM, v.zoom / 1.2),
                            }))
                        }
                    >
                        −
                    </button>
                    <button
                        type="button"
                        className={styles.toolBtn}
                        onClick={reset}
                    >
                        reset
                    </button>
                    <span className={styles.zoomReadout}>
                        {Math.round(view.zoom * 100)}%
                    </span>
                </div>
                <div
                    ref={viewportRef}
                    className={styles.viewport}
                    tabIndex={0}
                    onWheel={onWheel}
                    onMouseDown={onMouseDown}
                    onKeyDown={onKeyDown}
                >
                    <div
                        ref={canvasRef}
                        className={`${styles.canvas} ${animating ? styles.canvasAnim : ""}`}
                        style={{
                            transform: `translate(${view.x}px, ${view.y}px) scale(${view.zoom})`,
                        }}
                    >
                        {children}
                    </div>
                </div>
            </div>
        </InterpretationContext.Provider>
    );
}
