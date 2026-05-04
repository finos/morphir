/**
 * Decimal type — corresponds to `specs/language/expressions/decimal.md`.
 *
 * Decimal is a Number instance; its operations are inherited from the
 * Number type class. This module declares the type metadata only.
 */

export const modulePath = "expressions/decimal.md";

/** Decimal attributes. */
export interface DecimalAttributes {
    readonly totalDigits: number;
    readonly fractionalDigits: number;
}
