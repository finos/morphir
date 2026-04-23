/**
 * Integer type — corresponds to `specs/language/expressions/integer.md`.
 *
 * Integer is a Number instance; its operations are inherited from the
 * Number type class. This module declares the type metadata only.
 */

export const modulePath = "expressions/integer.md";

/** Integer attributes. */
export interface IntegerAttributes {
    readonly sizeInBits?: number;
    readonly signed?: boolean;
}
