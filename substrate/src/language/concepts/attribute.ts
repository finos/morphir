/**
 * Attribute concept — corresponds to `specs/language/concepts/attribute.md`.
 *
 * Attributes are fixed configuration values attached to a type instance
 * (e.g., precision on Decimal, size on Integer).
 */

/** A declared attribute with its name and type reference. */
export interface AttributeDecl {
    readonly name: string;
    readonly typeRef: string;
    readonly optionality: "required" | "optional";
}
