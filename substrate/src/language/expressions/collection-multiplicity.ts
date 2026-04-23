/**
 * Collection Multiplicity attribute type —
 * corresponds to `specs/language/expressions/collection-multiplicity.md`.
 *
 * Member values: unique, multi.
 */

export const modulePath = "expressions/collection-multiplicity.md";

export const MEMBERS = ["unique", "multi"] as const;

export type CollectionMultiplicity = (typeof MEMBERS)[number];
