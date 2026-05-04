/**
 * Collection Iteration Order attribute type —
 * corresponds to `specs/language/expressions/collection-iteration-order.md`.
 *
 * Member values: none, insertion, key.
 */

export const modulePath = "expressions/collection-iteration-order.md";

export const MEMBERS = ["none", "insertion", "key"] as const;

export type CollectionIterationOrder = (typeof MEMBERS)[number];
