/**
 * UML-style visualisation of a sum (one-of) type: a parent box at the
 * top, an edge labelled "one of", and a row of subtype boxes
 * underneath. Each box may carry a `srcId` that links it back to a
 * phrase in the surrounding prose so the viewer can cross-highlight
 * on hover.
 */
import type { JSX, ReactNode } from "react";
import styles from "./TypeDiagram.module.css";

export interface TypeVariant {
    readonly name: string;
    readonly srcId?: string;
    readonly detail?: ReactNode;
}

export interface TypeDiagramProps {
    readonly parentName: string;
    readonly parentSrcId?: string;
    readonly edgeLabel?: string;
    readonly variants: readonly TypeVariant[];
}

export function TypeDiagram({
    parentName,
    parentSrcId,
    edgeLabel = "one of",
    variants,
}: TypeDiagramProps): JSX.Element {
    return (
        <div className={styles.diagram}>
            <div className={styles.parentRow}>
                <div
                    className={`${styles.node} ${styles.parent}`}
                    {...(parentSrcId ? { "data-src-id": parentSrcId } : {})}
                >
                    <div className={styles.nodeKind}>type</div>
                    <div className={styles.nodeName}>{parentName}</div>
                </div>
            </div>
            <div className={styles.trunk} aria-hidden="true" />
            <div className={styles.edgeLabel}>{edgeLabel}</div>
            <div className={styles.bus} aria-hidden="true" />
            <div className={styles.childrenRow}>
                {variants.map((v, i) => (
                    <div key={`${v.name}-${i}`} className={styles.childWrap}>
                        <div className={styles.riser} aria-hidden="true" />
                        <div
                            className={`${styles.node} ${styles.child}`}
                            {...(v.srcId ? { "data-src-id": v.srcId } : {})}
                        >
                            <div className={styles.nodeKind}>variant</div>
                            <div className={styles.nodeName}>{v.name}</div>
                            {v.detail !== undefined && v.detail !== null && (
                                <div className={styles.nodeDetail}>
                                    {v.detail}
                                </div>
                            )}
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
}
