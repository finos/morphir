/**
 * Ordering Relation type — corresponds to `specs/language/expressions/ordering-relation.md`.
 *
 * A type with three member values: Less, Equal, Greater.
 * No operations of its own.
 */

export const modulePath = "expressions/ordering-relation.md";

/** The three member values of the Ordering Relation type. */
export const MEMBERS = ["Less", "Equal", "Greater"] as const;

export type OrderingRelation = (typeof MEMBERS)[number];
