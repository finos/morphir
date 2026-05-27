/**
 * Wraps a single expression-tree node in a fixed-size slot. The
 * children render at their natural (unconstrained) size inside an
 * inner container; we measure that container with a ResizeObserver
 * and then apply a CSS scale transform so it fits inside the slot.
 *
 * Because the slot itself is hardcoded per kind (see slotSizes.ts),
 * the parent's layout is unaffected by however large or complex the
 * child turns out to be — that is the whole point of this rendering
 * model.
 */
import {
    useContext,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
    type JSX,
    type ReactNode,
} from "react";
import { InterpretationContext } from "./context";
import {
    PLACEHOLDER_SCALE_THRESHOLD,
    SLOT_SIZES,
    type SlotKind,
} from "./slotSizes";
import styles from "./NodeSlot.module.css";

export interface NodeSlotProps {
    readonly kind: SlotKind;
    /** Short tag rendered as the placeholder when zoomed too far out. */
    readonly label?: string;
    readonly children: ReactNode;
}

export function NodeSlot({
    kind,
    label,
    children,
}: NodeSlotProps): JSX.Element {
    const slot = SLOT_SIZES[kind];
    const slotRef = useRef<HTMLDivElement | null>(null);
    const naturalRef = useRef<HTMLDivElement | null>(null);
    const [natural, setNatural] = useState<{ w: number; h: number }>({
        w: slot.width,
        h: slot.height,
    });

    const ctx = useContext(InterpretationContext);

    const measure = (): void => {
        const el = naturalRef.current;
        if (!el) return;
        // offsetWidth/Height ignore CSS transforms, giving us the true
        // pre-scale layout size — exactly what we need to compute the
        // fit ratio.
        const w = el.offsetWidth;
        const h = el.offsetHeight;
        if (w > 0 && h > 0) {
            setNatural((prev) =>
                prev.w === w && prev.h === h ? prev : { w, h },
            );
        }
    };

    useLayoutEffect(() => {
        measure();
        // intentionally only react to children identity changing
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [children]);

    useEffect(() => {
        const el = naturalRef.current;
        if (!el || typeof ResizeObserver === "undefined") return;
        const ro = new ResizeObserver(() => measure());
        ro.observe(el);
        return () => ro.disconnect();
    }, []);

    const scale = Math.min(
        slot.width / Math.max(natural.w, 1),
        slot.height / Math.max(natural.h, 1),
        1,
    );

    const effectiveScale = ctx.effectiveScale * scale;
    const showPlaceholder = effectiveScale < PLACEHOLDER_SCALE_THRESHOLD;

    const childCtx = useMemo(
        () => ({
            effectiveScale,
            requestZoomTo: ctx.requestZoomTo,
        }),
        [effectiveScale, ctx.requestZoomTo],
    );

    const onClick = (e: React.MouseEvent<HTMLDivElement>): void => {
        // Don't hijack clicks on actual links/buttons. We intentionally do
        // NOT bail on `[data-src-id]` — those mark prose-linked rows and
        // sub-elements inside the slot (e.g. every <tr> of a decision
        // table), so excluding them would make most of the slot's area
        // un-zoomable.
        const t = e.target as HTMLElement | null;
        if (t?.closest("a, button")) return;
        if (slotRef.current) {
            // Stop here so the click doesn't keep bubbling and trigger
            // an *ancestor* slot's zoom on top of ours — we always want
            // to zoom to the innermost clicked slot.
            e.stopPropagation();
            ctx.requestZoomTo({ element: slotRef.current });
        }
    };

    return (
        <div
            ref={slotRef}
            className={`${styles.slot} ${styles[`slot-${kind}`] ?? ""}`}
            style={{ width: slot.width, height: slot.height }}
            data-slot-kind={kind}
            onClick={onClick}
        >
            {showPlaceholder ? (
                <div className={styles.placeholder} aria-hidden="true">
                    <span className={styles.placeholderLabel}>
                        {label ?? kind}
                    </span>
                </div>
            ) : (
                <div
                    ref={naturalRef}
                    className={styles.natural}
                    style={{
                        transform: `scale(${scale})`,
                        transformOrigin: "top left",
                    }}
                >
                    <InterpretationContext.Provider value={childCtx}>
                        {children}
                    </InterpretationContext.Provider>
                </div>
            )}
        </div>
    );
}
