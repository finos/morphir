/**
 * Substrate-specific attribute shapes for the Morphir IR.
 *
 * These are the concrete attribute types used when substrate loads a
 * `morphir.json` distribution.  The two shapes are intentionally distinct:
 *
 * - `TypeAttrs`  — carried on every `Type` node (currently just the optional
 *   source-location anchor; morphir-elm today emits `{}` for `ta`).
 * - `ValueAttrs` — carried on every `Value` and `Pattern` node; includes the
 *   inferred `Type<{}>` that morphir-elm already emits for `va`, **plus** the
 *   optional source-location slot that future morphir-elm versions will fill.
 *
 * When morphir-elm starts emitting source locations the codec decoder in
 * `src/ir/codec.ts` is the single edit point — these shapes do not change.
 */

import type { SourceLocation } from "../substrate/ast.js";
import type { Distribution, Type } from "./distribution.js";

/**
 * Attribute carried on type-level IR nodes (`Type<TypeAttrs>`).
 *
 * Today morphir-elm emits `{}` for type attributes; `src` is absent but the
 * slot is ready for when morphir-elm starts emitting it.
 */
export interface TypeAttrs {
    readonly src?: SourceLocation;
}

/**
 * Attribute carried on value-level IR nodes (`Value<TypeAttrs, ValueAttrs>`
 * and `Pattern<ValueAttrs>`).
 *
 * `type` is the inferred `Type<{}>` that morphir-elm emits today as the `va`
 * slot.  `src` will be non-null once morphir-elm emits source locations.
 */
export interface ValueAttrs {
    readonly src?: SourceLocation;
    readonly type: Type<{}>;
}

/** The flavored distribution that substrate works with end-to-end. */
export type SubstrateDistribution = Distribution<TypeAttrs, ValueAttrs>;
