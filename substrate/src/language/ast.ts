import type { Root, Heading } from "mdast";

/** A runtime value used in test cases and evaluation. */
export type Value = number | boolean | string;

/**
 * Concept kind detected from a heading's link target.
 * Each kind corresponds to a concept module under `specs/language/concepts/`.
 */
export type ConceptKind =
    | "type"
    | "type-class"
    | "operation"
    | "record"
    | "choice"
    | "decision-table"
    | "provenance";

/** An operation parsed from a spec document. */
export interface OperationNode {
    readonly name: string;
    readonly marker: "required" | "derived" | "none";
    readonly testCases: TestCaseTable | null;
    readonly line?: number | undefined;
}

/** A table of test cases extracted from a markdown table. */
export interface TestCaseTable {
    readonly headers: readonly string[];
    readonly rows: readonly TestCaseRow[];
}

/** A single row of test case data. Last cell is the expected output. */
export interface TestCaseRow {
    readonly cells: readonly Value[];
}

/**
 * An expression in a user module definition.
 *
 * - `literal`: a constant value (number, boolean, or string).
 * - `var`: a named variable referencing an input or earlier definition.
 * - `call`: an operation call with arguments (prefix or infix form).
 */
export type Expr =
    | { readonly kind: "literal"; readonly value: Value }
    | { readonly kind: "var"; readonly name: string }
    | { readonly kind: "call"; readonly op: string; readonly args: readonly Expr[] };

/** A definition within a user module. */
export interface UserDefinition {
    readonly name: string;
    readonly expr: Expr;
    readonly testCases: TestCaseTable | null;
}

/** A parsed user module. */
export interface UserModule {
    readonly title: string;
    readonly inputs: readonly string[];
    readonly definitions: readonly UserDefinition[];
}

/** A link reference found during document traversal. */
export interface LinkRef {
    readonly url: string;
    readonly text: string;
    readonly line?: number;
    readonly column?: number;
}

/**
 * The kind of document, determined by the h1 heading's concept link.
 */
export type DocumentKind =
    | { readonly type: "type"; readonly name: string }
    | { readonly type: "type-class"; readonly name: string }
    | { readonly type: "user-module"; readonly name: string }
    | { readonly type: "concept"; readonly concept: ConceptKind; readonly name: string }
    | { readonly type: "unknown" };

/**
 * A parsed substrate document: the MDAST root plus extracted metadata.
 */
export interface SubstrateDocument {
    readonly filePath: string;
    readonly root: Root;
    readonly title: string;
    readonly kind: DocumentKind;
}
