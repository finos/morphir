/**
 * Optionality concept — corresponds to `specs/language/concepts/optionality.md`.
 *
 * Provides utilities for detecting and validating optionality markers
 * on slots (fields, parameters, attributes).
 */

/** The two optionality states a slot can be in. */
export type OptionalityState = "required" | "optional";

/**
 * Parse an optionality marker from a field declaration string.
 *
 * Recognised values (case-insensitive): "required", "optional".
 * Defaults to "required" when absent or unrecognised.
 */
export function parseOptionality(raw: string): OptionalityState {
    const lower = raw.trim().toLowerCase();
    if (lower === "optional") return "optional";
    return "required";
}
