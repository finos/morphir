/**
 * Substrate interpretation AST. A `Module` is the entry point an LLM
 * (or human author) derives from the markdown document; the dev viewer
 * renders the AST directly instead of pattern-matching YAML shapes.
 *
 * Every node carries a list of `SourceLocation`s pointing back at the
 * prose spans that support it. A single node may have multiple anchors
 * (multi-paragraph definitions).
 */

export interface SourceLocation {
    readonly file: string;
    readonly sectionId: string;
    readonly text: string;
}

export interface Module {
    readonly types: ReadonlyMap<string, TypeDefinition>;
    readonly values: ReadonlyMap<string, ValueDefinition>;
    readonly src: readonly SourceLocation[];
    /**
     * Timestamp at which the interpretation (pros + descriptions) was
     * last reviewed against the prose. Compared against the markdown
     * file's mtime to flag the interpretation as outdated when the
     * prose has been edited since this review.
     */
    readonly lastInterpretedAt?: Date;
}

// --- Types ---------------------------------------------------------------

export type TypeDefinition = OneOfType;

export interface OneOfType {
    readonly kind: "one-of";
    readonly variants: readonly Variant[];
    readonly src: readonly SourceLocation[];
}

export interface Variant {
    readonly name: string;
    readonly payload?: TypeRef;
    readonly src: readonly SourceLocation[];
}

export interface TypeRef {
    readonly name: string;
    readonly src: readonly SourceLocation[];
}

// --- Values --------------------------------------------------------------

export interface ValueDefinition {
    readonly params: readonly string[];
    readonly body: ValueExpression;
    readonly src: readonly SourceLocation[];
}

export type ValueExpression =
    | Literal
    | Variable
    | IfExpr
    | MatchExpr
    | Apply;

export type Literal =
    | {
          readonly kind: "literal-string";
          readonly value: string;
          readonly src: readonly SourceLocation[];
      }
    | {
          readonly kind: "literal-number";
          readonly value: number;
          readonly src: readonly SourceLocation[];
      }
    | {
          readonly kind: "literal-boolean";
          readonly value: boolean;
          readonly src: readonly SourceLocation[];
      }
    | {
          readonly kind: "literal-null";
          readonly src: readonly SourceLocation[];
      };

export interface Variable {
    readonly kind: "variable";
    readonly name: string;
    readonly src: readonly SourceLocation[];
}

export interface IfExpr {
    readonly kind: "if";
    readonly condition: ValueExpression;
    readonly then: ValueExpression;
    readonly else: ValueExpression;
    readonly src: readonly SourceLocation[];
}

export interface MatchExpr {
    readonly kind: "match";
    readonly on: ValueExpression;
    readonly cases: readonly MatchCase[];
    readonly src: readonly SourceLocation[];
}

export interface MatchCase {
    readonly when: ValueExpression;
    readonly then: ValueExpression;
    readonly src: readonly SourceLocation[];
}

// --- Apply: one variant per operator ------------------------------------

type BinOp<K extends string> = {
    readonly kind: K;
    readonly left: ValueExpression;
    readonly right: ValueExpression;
    readonly src: readonly SourceLocation[];
};

type UnaryOp<K extends string> = {
    readonly kind: K;
    readonly operand: ValueExpression;
    readonly src: readonly SourceLocation[];
};

type NaryOp<K extends string> = {
    readonly kind: K;
    readonly args: readonly ValueExpression[];
    readonly src: readonly SourceLocation[];
};

export type Apply =
    // Comparison
    | BinOp<"equals">
    | BinOp<"not-equals">
    | BinOp<"less-than">
    | BinOp<"less-than-or-equal">
    | BinOp<"greater-than">
    | BinOp<"greater-than-or-equal">
    // Logical
    | NaryOp<"and">
    | NaryOp<"or">
    | UnaryOp<"not">
    // Arithmetic
    | BinOp<"add">
    | BinOp<"subtract">
    | BinOp<"multiply">
    | BinOp<"divide">
    // String
    | NaryOp<"concat">
    | BinOp<"contains">
    | BinOp<"starts-with">
    | BinOp<"ends-with">;

export type ApplyKind = Apply["kind"];

export const BINARY_OPS = [
    "equals",
    "not-equals",
    "less-than",
    "less-than-or-equal",
    "greater-than",
    "greater-than-or-equal",
    "add",
    "subtract",
    "multiply",
    "divide",
    "contains",
    "starts-with",
    "ends-with",
] as const satisfies readonly ApplyKind[];

export const UNARY_OPS = ["not"] as const satisfies readonly ApplyKind[];

export const NARY_OPS = [
    "and",
    "or",
    "concat",
] as const satisfies readonly ApplyKind[];

// --- Diagnostics --------------------------------------------------------

export type DiagnosticSeverity = "error" | "warning";

export interface ParseDiagnostic {
    readonly severity: DiagnosticSeverity;
    readonly message: string;
    readonly position?: { readonly line: number; readonly col: number };
    readonly path?: readonly (string | number)[];
}

export interface ParseResult {
    readonly module?: Module;
    readonly diagnostics: readonly ParseDiagnostic[];
}
