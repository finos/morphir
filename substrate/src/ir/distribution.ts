/**
 * TypeScript port of the Morphir IR type shapes.
 *
 * Mirrors `src/Morphir/IR/*.elm` in the morphir-elm reference implementation,
 * but keeps the attribute type parameters (`TA`, `VA`) threaded all the way up
 * to `Distribution` instead of binding them at that level (as Elm's
 * `Distribution.Library` does).  The "no attributes" case is simply
 * `Distribution<{}, {}>`.
 *
 * Reference: morphir-elm/src/Morphir/IR/
 */

// ---------------------------------------------------------------------------
// Identifiers
// ---------------------------------------------------------------------------

/** A name is a sequence of lower-case words, e.g. `["my", "type"]`. */
export type Name = readonly string[];

/** A path is a sequence of names, e.g. `[["module", "a"], ["sub"]]`. */
export type Path = readonly Name[];

/** A fully-qualified name: `[packagePath, modulePath, localName]`. */
export type FQName = readonly [Path, Path, Name];

// ---------------------------------------------------------------------------
// Access control
// ---------------------------------------------------------------------------

export type Access = "Public" | "Private";

export interface AccessControlled<T> {
    readonly access: Access;
    readonly value: T;
}

// ---------------------------------------------------------------------------
// Documentation wrapper
// ---------------------------------------------------------------------------

export interface Documented<T> {
    readonly doc: string;
    readonly value: T;
}

// ---------------------------------------------------------------------------
// Literals
// ---------------------------------------------------------------------------

export type Literal =
    | { readonly kind: "BoolLiteral"; readonly value: boolean }
    | { readonly kind: "CharLiteral"; readonly value: string }
    | { readonly kind: "StringLiteral"; readonly value: string }
    | { readonly kind: "WholeNumberLiteral"; readonly value: number }
    | { readonly kind: "FloatLiteral"; readonly value: number }
    | { readonly kind: "DecimalLiteral"; readonly value: string };

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Field<A> {
    readonly name: Name;
    readonly tpe: Type<A>;
}

/** Constructors: array of `[constructorName, [[argName, argType], ...]]`. */
export type Constructors<A> = ReadonlyArray<readonly [Name, ReadonlyArray<readonly [Name, Type<A>]>]>;

export type TypeSpecification<A> =
    | { readonly kind: "TypeAliasSpecification"; readonly params: readonly Name[]; readonly expr: Type<A> }
    | { readonly kind: "OpaqueTypeSpecification"; readonly params: readonly Name[] }
    | { readonly kind: "CustomTypeSpecification"; readonly params: readonly Name[]; readonly constructors: Constructors<A> }
    | {
        readonly kind: "DerivedTypeSpecification";
        readonly params: readonly Name[];
        readonly baseType: Type<A>;
        readonly fromBaseType: FQName;
        readonly toBaseType: FQName;
    };

export type TypeDefinition<A> =
    | { readonly kind: "TypeAliasDefinition"; readonly params: readonly Name[]; readonly expr: Type<A> }
    | { readonly kind: "CustomTypeDefinition"; readonly params: readonly Name[]; readonly constructors: AccessControlled<Constructors<A>> };

export type Type<A> =
    | { readonly kind: "Variable"; readonly attrs: A; readonly name: Name }
    | { readonly kind: "Reference"; readonly attrs: A; readonly name: FQName; readonly typeParams: readonly Type<A>[] }
    | { readonly kind: "Tuple"; readonly attrs: A; readonly elements: readonly Type<A>[] }
    | { readonly kind: "Record"; readonly attrs: A; readonly fields: readonly Field<A>[] }
    | { readonly kind: "ExtensibleRecord"; readonly attrs: A; readonly name: Name; readonly fields: readonly Field<A>[] }
    | { readonly kind: "Function"; readonly attrs: A; readonly argumentType: Type<A>; readonly returnType: Type<A> }
    | { readonly kind: "Unit"; readonly attrs: A };

// ---------------------------------------------------------------------------
// Values & Patterns
// ---------------------------------------------------------------------------

export type ValueSpecification<TA> = {
    readonly inputs: ReadonlyArray<readonly [Name, Type<TA>]>;
    readonly output: Type<TA>;
};

export type ValueDefinition<TA, VA> = {
    readonly inputTypes: ReadonlyArray<readonly [Name, VA, Type<TA>]>;
    readonly outputType: Type<TA>;
    readonly body: Value<TA, VA>;
};

/**
 * Patterns carry the same attribute type as value nodes (`VA`), mirroring
 * morphir-elm where `Pattern a` uses the same `a` threaded through values.
 */
export type Pattern<A> =
    | { readonly kind: "WildcardPattern"; readonly attrs: A }
    | { readonly kind: "AsPattern"; readonly attrs: A; readonly pattern: Pattern<A>; readonly name: Name }
    | { readonly kind: "TuplePattern"; readonly attrs: A; readonly elements: readonly Pattern<A>[] }
    | { readonly kind: "ConstructorPattern"; readonly attrs: A; readonly name: FQName; readonly args: readonly Pattern<A>[] }
    | { readonly kind: "EmptyListPattern"; readonly attrs: A }
    | { readonly kind: "HeadTailPattern"; readonly attrs: A; readonly head: Pattern<A>; readonly tail: Pattern<A> }
    | { readonly kind: "LiteralPattern"; readonly attrs: A; readonly literal: Literal }
    | { readonly kind: "UnitPattern"; readonly attrs: A };

export type Value<TA, VA> =
    | { readonly kind: "Literal"; readonly attrs: VA; readonly literal: Literal }
    | { readonly kind: "Constructor"; readonly attrs: VA; readonly name: FQName }
    | { readonly kind: "Tuple"; readonly attrs: VA; readonly elements: readonly Value<TA, VA>[] }
    | { readonly kind: "List"; readonly attrs: VA; readonly items: readonly Value<TA, VA>[] }
    | { readonly kind: "Record"; readonly attrs: VA; readonly fields: ReadonlyArray<readonly [Name, Value<TA, VA>]> }
    | { readonly kind: "Variable"; readonly attrs: VA; readonly name: Name }
    | { readonly kind: "Reference"; readonly attrs: VA; readonly name: FQName }
    | { readonly kind: "Field"; readonly attrs: VA; readonly subject: Value<TA, VA>; readonly fieldName: Name }
    | { readonly kind: "FieldFunction"; readonly attrs: VA; readonly name: Name }
    | { readonly kind: "Apply"; readonly attrs: VA; readonly function: Value<TA, VA>; readonly argument: Value<TA, VA> }
    | { readonly kind: "Lambda"; readonly attrs: VA; readonly argumentPattern: Pattern<VA>; readonly body: Value<TA, VA> }
    | {
        readonly kind: "LetDefinition";
        readonly attrs: VA;
        readonly name: Name;
        readonly definition: ValueDefinition<TA, VA>;
        readonly inValue: Value<TA, VA>;
    }
    | {
        readonly kind: "LetRecursion";
        readonly attrs: VA;
        readonly definitions: ReadonlyArray<readonly [Name, ValueDefinition<TA, VA>]>;
        readonly inValue: Value<TA, VA>;
    }
    | {
        readonly kind: "Destructure";
        readonly attrs: VA;
        readonly pattern: Pattern<VA>;
        readonly valueToDestruct: Value<TA, VA>;
        readonly inValue: Value<TA, VA>;
    }
    | {
        readonly kind: "IfThenElse";
        readonly attrs: VA;
        readonly condition: Value<TA, VA>;
        readonly thenBranch: Value<TA, VA>;
        readonly elseBranch: Value<TA, VA>;
    }
    | {
        readonly kind: "PatternMatch";
        readonly attrs: VA;
        readonly subject: Value<TA, VA>;
        readonly cases: ReadonlyArray<readonly [Pattern<VA>, Value<TA, VA>]>;
    }
    | {
        readonly kind: "UpdateRecord";
        readonly attrs: VA;
        readonly subject: Value<TA, VA>;
        readonly fields: ReadonlyArray<readonly [Name, Value<TA, VA>]>;
    }
    | { readonly kind: "Unit"; readonly attrs: VA };

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

export interface ModuleSpecification<TA> {
    readonly types: ReadonlyArray<readonly [Name, Documented<TypeSpecification<TA>>]>;
    readonly values: ReadonlyArray<readonly [Name, Documented<ValueSpecification<TA>>]>;
    readonly doc: string | null;
}

export interface ModuleDefinition<TA, VA> {
    readonly types: ReadonlyArray<readonly [Name, AccessControlled<Documented<TypeDefinition<TA>>>]>;
    readonly values: ReadonlyArray<readonly [Name, AccessControlled<Documented<ValueDefinition<TA, VA>>>]>;
    readonly doc: string | null;
}

// ---------------------------------------------------------------------------
// Packages
// ---------------------------------------------------------------------------

export interface PackageSpecification<TA> {
    readonly modules: ReadonlyArray<readonly [Path, ModuleSpecification<TA>]>;
}

export interface PackageDefinition<TA, VA> {
    readonly modules: ReadonlyArray<readonly [Path, AccessControlled<ModuleDefinition<TA, VA>>]>;
}

// ---------------------------------------------------------------------------
// Distribution
// ---------------------------------------------------------------------------

/**
 * A Morphir IR distribution.  Substrate keeps the attribute slots unbound so
 * the same shape can host any payload without forking the type tree.
 *
 * Wire format (versioned):
 * ```json
 * { "formatVersion": 3, "distribution": ["Library", packagePath, deps, def] }
 * ```
 */
export type Distribution<TA, VA> = {
    readonly kind: "Library";
    readonly packageName: Path;
    /** Dependencies: array of `[packagePath, packageSpecification]`. */
    readonly dependencies: ReadonlyArray<readonly [Path, PackageSpecification<TA>]>;
    readonly packageDef: PackageDefinition<TA, VA>;
};
