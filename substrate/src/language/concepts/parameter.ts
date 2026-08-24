/**
 * Parameter concept — corresponds to `specs/language/concepts/parameter.md`.
 *
 * Parameters make a type generic over other types (e.g., Collection<T>).
 */

/** A declared type parameter. */
export interface ParameterDecl {
    readonly name: string;
    readonly constraint?: string;
}
