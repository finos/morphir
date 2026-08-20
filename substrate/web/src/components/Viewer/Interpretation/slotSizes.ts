/**
 * Fixed slot sizes for each expression-tree node kind in the
 * interpretation visualisation. These do NOT adapt to content: a
 * decision-table slot is always the same size whether it has 3 rules
 * or 30. Content is scaled to fit via CSS transforms in NodeSlot,
 * which is what keeps the parent's visual shape stable regardless of
 * how complex the children are.
 */

export type SlotKind =
    | "decision-tree"
    | "decision-table"
    | "type-diagram"
    | "apply"
    | "ir-module"
    | "ir-type"
    | "ir-value"
    | "ir-expr"
    | "ir-pattern";

export interface SlotSize {
    readonly width: number;
    readonly height: number;
}

export const SLOT_SIZES: Record<SlotKind, SlotSize> = {
    "decision-tree": { width: 520, height: 130 },
    "decision-table": { width: 520, height: 360 },
    "type-diagram": { width: 360, height: 240 },
    apply: { width: 240, height: 80 },
    "ir-module": { width: 720, height: 520 },
    "ir-type": { width: 440, height: 200 },
    "ir-value": { width: 480, height: 240 },
    "ir-expr": { width: 320, height: 140 },
    "ir-pattern": { width: 200, height: 60 },
};

/**
 * Effective scale (root zoom × product of ancestor slot scales) below
 * which a NodeSlot renders a placeholder instead of its actual
 * content. Compounded CSS transforms get illegible quickly; the
 * cutoff stops us from painting thousands of unreadable nested
 * elements. The slot itself still occupies the full reserved space,
 * so layout above is unaffected.
 */
export const PLACEHOLDER_SCALE_THRESHOLD = 0.15;
