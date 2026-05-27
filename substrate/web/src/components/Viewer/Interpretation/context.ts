/**
 * React context plumbing for the interpretation viewport. Two pieces
 * of state flow down through context:
 *
 *  - `effectiveScale`: the product of the root viewport zoom and
 *    every NodeSlot's own scale along the path from the viewport to
 *    the current node. Used to decide whether a NodeSlot is too
 *    small to be worth rendering in detail.
 *
 *  - `requestZoomTo`: a callback the viewport hands to NodeSlots so
 *    clicking a slot can animate the viewport transform to bring
 *    that slot back to (approximately) its natural size.
 */
import { createContext } from "react";

export interface ZoomTarget {
    readonly element: HTMLElement;
}

export interface InterpretationContextValue {
    readonly effectiveScale: number;
    readonly requestZoomTo: (target: ZoomTarget) => void;
}

export const InterpretationContext =
    createContext<InterpretationContextValue>({
        effectiveScale: 1,
        requestZoomTo: () => {},
    });
