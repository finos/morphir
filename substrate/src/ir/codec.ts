/**
 * JSON codec for the Morphir IR Distribution.
 *
 * Mirrors `src/Morphir/IR/Distribution/Codec.elm` and the sub-codecs it
 * delegates to, but parameterized by attribute decoders/encoders so the same
 * codec can serve different attribute payloads without forking.
 *
 * The decoder is the priority for Phase 1.  The encoder is included for
 * round-trip tests.
 *
 * Wire format reference: `morphir-elm/tests/Morphir/IR/Distribution/CodecTests.elm`
 *
 * Top-level versioned format:
 * ```json
 * { "formatVersion": 3, "distribution": [...] }
 * ```
 */

import type {
    Access,
    AccessControlled,
    Constructors,
    Distribution,
    Documented,
    Field,
    FQName,
    Literal,
    ModuleDefinition,
    ModuleSpecification,
    Name,
    PackageDefinition,
    PackageSpecification,
    Path,
    Pattern,
    Type,
    TypeDefinition,
    TypeSpecification,
    Value,
    ValueDefinition,
    ValueSpecification,
} from "./distribution.js";

import type { TypeAttrs, ValueAttrs, SubstrateDistribution } from "./attrs.js";

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

export class DecodeError extends Error {
    constructor(
        message: string,
        /** JSON path to the problematic node, e.g. `["distribution", 3, "modules", 0]`. */
        public readonly path: (string | number)[] = [],
    ) {
        super(message);
        this.name = "DecodeError";
    }
}

// ---------------------------------------------------------------------------
// Decoder type alias
// ---------------------------------------------------------------------------

type Decoder<T> = (json: unknown) => T;
type Encoder<T> = (value: T) => unknown;

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

function str(json: unknown): string {
    if (typeof json !== "string") throw new DecodeError(`Expected string, got ${typeof json}`);
    return json;
}

function num(json: unknown): number {
    if (typeof json !== "number") throw new DecodeError(`Expected number, got ${typeof json}`);
    return json;
}

function bool(json: unknown): boolean {
    if (typeof json !== "boolean") throw new DecodeError(`Expected boolean, got ${typeof json}`);
    return json;
}

function arr(json: unknown): unknown[] {
    if (!Array.isArray(json)) throw new DecodeError(`Expected array, got ${typeof json}`);
    return json;
}

function obj(json: unknown): Record<string, unknown> {
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        throw new DecodeError(`Expected object, got ${Array.isArray(json) ? "array" : typeof json}`);
    }
    return json as Record<string, unknown>;
}

function idx(a: unknown[], i: number): unknown {
    const v = arr(a)[i];
    if (v === undefined) throw new DecodeError(`Missing index ${i}`);
    return v;
}

function field(o: unknown, key: string): unknown {
    const rec = obj(o);
    if (!(key in rec)) throw new DecodeError(`Missing field "${key}"`);
    return rec[key];
}

function optField(o: unknown, key: string): unknown | undefined {
    const rec = obj(o);
    return rec[key];
}

function tag(a: unknown[]): string {
    return str(idx(a, 0));
}

// ---------------------------------------------------------------------------
// Name / Path / FQName
// ---------------------------------------------------------------------------

function decodeName(json: unknown): Name {
    return arr(json).map(str);
}

function encodeName(name: Name): unknown {
    return [...name];
}

function decodePath(json: unknown): Path {
    return arr(json).map(decodeName);
}

function encodePath(path: Path): unknown {
    return path.map(encodeName);
}

function decodeFQName(json: unknown): FQName {
    const a = arr(json);
    return [decodePath(idx(a, 0)), decodePath(idx(a, 1)), decodeName(idx(a, 2))];
}

function encodeFQName(fqn: FQName): unknown {
    return [encodePath(fqn[0]), encodePath(fqn[1]), encodeName(fqn[2])];
}

// ---------------------------------------------------------------------------
// Literal
// ---------------------------------------------------------------------------

function decodeLiteral(json: unknown): Literal {
    const a = arr(json);
    const k = tag(a);
    switch (k) {
        case "BoolLiteral":
            return { kind: "BoolLiteral", value: bool(idx(a, 1)) };
        case "CharLiteral":
            return { kind: "CharLiteral", value: str(idx(a, 1)) };
        case "StringLiteral":
            return { kind: "StringLiteral", value: str(idx(a, 1)) };
        case "WholeNumberLiteral":
            return { kind: "WholeNumberLiteral", value: num(idx(a, 1)) };
        case "FloatLiteral":
            return { kind: "FloatLiteral", value: num(idx(a, 1)) };
        case "DecimalLiteral":
            return { kind: "DecimalLiteral", value: str(idx(a, 1)) };
        default:
            throw new DecodeError(`Unknown Literal kind: ${k}`);
    }
}

function encodeLiteral(lit: Literal): unknown {
    switch (lit.kind) {
        case "BoolLiteral": return ["BoolLiteral", lit.value];
        case "CharLiteral": return ["CharLiteral", lit.value];
        case "StringLiteral": return ["StringLiteral", lit.value];
        case "WholeNumberLiteral": return ["WholeNumberLiteral", lit.value];
        case "FloatLiteral": return ["FloatLiteral", lit.value];
        case "DecimalLiteral": return ["DecimalLiteral", lit.value];
    }
}

// ---------------------------------------------------------------------------
// Access / AccessControlled
// ---------------------------------------------------------------------------

function decodeAccess(json: unknown): Access {
    const s = str(json);
    if (s !== "Public" && s !== "Private") throw new DecodeError(`Unknown Access: ${s}`);
    return s;
}

function encodeAccess(a: Access): unknown {
    return a;
}

function decodeAccessControlled<T>(decodeValue: Decoder<T>): Decoder<AccessControlled<T>> {
    return (json) => {
        const o = obj(json);
        return {
            access: decodeAccess(field(o, "access")),
            value: decodeValue(field(o, "value")),
        };
    };
}

function encodeAccessControlled<T>(encodeValue: Encoder<T>): Encoder<AccessControlled<T>> {
    return (ac) => ({ access: encodeAccess(ac.access), value: encodeValue(ac.value) });
}

// ---------------------------------------------------------------------------
// Documented
// ---------------------------------------------------------------------------

function decodeDocumented<T>(decodeValue: Decoder<T>): Decoder<Documented<T>> {
    return (json) => {
        // morphir-elm emits `{ "doc": "...", "value": ... }` but also tolerates
        // bare values (see Documented.Codec.elm).
        if (typeof json === "object" && json !== null && !Array.isArray(json)) {
            const o = json as Record<string, unknown>;
            if ("doc" in o && "value" in o) {
                return { doc: str(o["doc"]), value: decodeValue(o["value"]) };
            }
        }
        return { doc: "", value: decodeValue(json) };
    };
}

function encodeDocumented<T>(encodeValue: Encoder<T>): Encoder<Documented<T>> {
    return (d) => ({ doc: d.doc, value: encodeValue(d.value) });
}

// ---------------------------------------------------------------------------
// Type<A>
// ---------------------------------------------------------------------------

export function decodeType<A>(decodeAttrs: Decoder<A>): Decoder<Type<A>> {
    const lazy = (): Decoder<Type<A>> => (json) => decodeType(decodeAttrs)(json);
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        switch (k) {
            case "Variable":
                return { kind: "Variable", attrs: decodeAttrs(idx(a, 1)), name: decodeName(idx(a, 2)) };
            case "Reference":
                return {
                    kind: "Reference",
                    attrs: decodeAttrs(idx(a, 1)),
                    name: decodeFQName(idx(a, 2)),
                    typeParams: (arr(idx(a, 3))).map(lazy()),
                };
            case "Tuple":
                return { kind: "Tuple", attrs: decodeAttrs(idx(a, 1)), elements: (arr(idx(a, 2))).map(lazy()) };
            case "Record":
                return {
                    kind: "Record",
                    attrs: decodeAttrs(idx(a, 1)),
                    fields: (arr(idx(a, 2))).map(decodeField(decodeAttrs)),
                };
            case "ExtensibleRecord":
                return {
                    kind: "ExtensibleRecord",
                    attrs: decodeAttrs(idx(a, 1)),
                    name: decodeName(idx(a, 2)),
                    fields: (arr(idx(a, 3))).map(decodeField(decodeAttrs)),
                };
            case "Function":
                return {
                    kind: "Function",
                    attrs: decodeAttrs(idx(a, 1)),
                    argumentType: lazy()(idx(a, 2)),
                    returnType: lazy()(idx(a, 3)),
                };
            case "Unit":
                return { kind: "Unit", attrs: decodeAttrs(idx(a, 1)) };
            default:
                throw new DecodeError(`Unknown Type kind: ${k}`);
        }
    };
}

export function encodeType<A>(encodeAttrs: Encoder<A>): Encoder<Type<A>> {
    const self = (): Encoder<Type<A>> => (v) => encodeType(encodeAttrs)(v);
    return (t) => {
        switch (t.kind) {
            case "Variable": return ["Variable", encodeAttrs(t.attrs), encodeName(t.name)];
            case "Reference": return ["Reference", encodeAttrs(t.attrs), encodeFQName(t.name), t.typeParams.map(self())];
            case "Tuple": return ["Tuple", encodeAttrs(t.attrs), t.elements.map(self())];
            case "Record": return ["Record", encodeAttrs(t.attrs), t.fields.map(encodeField(encodeAttrs))];
            case "ExtensibleRecord":
                return ["ExtensibleRecord", encodeAttrs(t.attrs), encodeName(t.name), t.fields.map(encodeField(encodeAttrs))];
            case "Function":
                return ["Function", encodeAttrs(t.attrs), self()(t.argumentType), self()(t.returnType)];
            case "Unit": return ["Unit", encodeAttrs(t.attrs)];
        }
    };
}

function decodeField<A>(decodeAttrs: Decoder<A>): Decoder<Field<A>> {
    return (json) => {
        const o = obj(json);
        return { name: decodeName(field(o, "name")), tpe: decodeType(decodeAttrs)(field(o, "tpe")) };
    };
}

function encodeField<A>(encodeAttrs: Encoder<A>): Encoder<Field<A>> {
    return (f) => ({ name: encodeName(f.name), tpe: encodeType(encodeAttrs)(f.tpe) });
}

// ---------------------------------------------------------------------------
// TypeSpecification / TypeDefinition
// ---------------------------------------------------------------------------

function decodeTypeSpecification<A>(decodeAttrs: Decoder<A>): Decoder<TypeSpecification<A>> {
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        switch (k) {
            case "TypeAliasSpecification":
                return {
                    kind: "TypeAliasSpecification",
                    params: (arr(idx(a, 1))).map(decodeName),
                    expr: decodeType(decodeAttrs)(idx(a, 2)),
                };
            case "OpaqueTypeSpecification":
                return { kind: "OpaqueTypeSpecification", params: (arr(idx(a, 1))).map(decodeName) };
            case "CustomTypeSpecification":
                return {
                    kind: "CustomTypeSpecification",
                    params: (arr(idx(a, 1))).map(decodeName),
                    constructors: decodeConstructors(decodeAttrs)(idx(a, 2)),
                };
            case "DerivedTypeSpecification": {
                const cfg = obj(idx(a, 2));
                return {
                    kind: "DerivedTypeSpecification",
                    params: (arr(idx(a, 1))).map(decodeName),
                    baseType: decodeType(decodeAttrs)(field(cfg, "baseType")),
                    fromBaseType: decodeFQName(field(cfg, "fromBaseType")),
                    toBaseType: decodeFQName(field(cfg, "toBaseType")),
                };
            }
            default:
                throw new DecodeError(`Unknown TypeSpecification kind: ${k}`);
        }
    };
}

function encodeTypeSpecification<A>(encodeAttrs: Encoder<A>): Encoder<TypeSpecification<A>> {
    return (spec) => {
        switch (spec.kind) {
            case "TypeAliasSpecification":
                return ["TypeAliasSpecification", spec.params.map(encodeName), encodeType(encodeAttrs)(spec.expr)];
            case "OpaqueTypeSpecification":
                return ["OpaqueTypeSpecification", spec.params.map(encodeName)];
            case "CustomTypeSpecification":
                return [
                    "CustomTypeSpecification",
                    spec.params.map(encodeName),
                    encodeConstructors(encodeAttrs)(spec.constructors),
                ];
            case "DerivedTypeSpecification":
                return [
                    "DerivedTypeSpecification",
                    spec.params.map(encodeName),
                    {
                        baseType: encodeType(encodeAttrs)(spec.baseType),
                        fromBaseType: encodeFQName(spec.fromBaseType),
                        toBaseType: encodeFQName(spec.toBaseType),
                    },
                ];
        }
    };
}

function decodeTypeDefinition<A>(decodeAttrs: Decoder<A>): Decoder<TypeDefinition<A>> {
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        switch (k) {
            case "TypeAliasDefinition":
                return {
                    kind: "TypeAliasDefinition",
                    params: (arr(idx(a, 1))).map(decodeName),
                    expr: decodeType(decodeAttrs)(idx(a, 2)),
                };
            case "CustomTypeDefinition":
                return {
                    kind: "CustomTypeDefinition",
                    params: (arr(idx(a, 1))).map(decodeName),
                    constructors: decodeAccessControlled(decodeConstructors(decodeAttrs))(idx(a, 2)),
                };
            default:
                throw new DecodeError(`Unknown TypeDefinition kind: ${k}`);
        }
    };
}

function encodeTypeDefinition<A>(encodeAttrs: Encoder<A>): Encoder<TypeDefinition<A>> {
    return (def) => {
        switch (def.kind) {
            case "TypeAliasDefinition":
                return ["TypeAliasDefinition", def.params.map(encodeName), encodeType(encodeAttrs)(def.expr)];
            case "CustomTypeDefinition":
                return [
                    "CustomTypeDefinition",
                    def.params.map(encodeName),
                    encodeAccessControlled(encodeConstructors(encodeAttrs))(def.constructors),
                ];
        }
    };
}

function decodeConstructors<A>(decodeAttrs: Decoder<A>): Decoder<Constructors<A>> {
    return (json) =>
        arr(json).map((entry) => {
            const a = arr(entry);
            const ctorName = decodeName(idx(a, 0));
            const args = arr(idx(a, 1)).map((argEntry) => {
                const aa = arr(argEntry);
                return [decodeName(idx(aa, 0)), decodeType(decodeAttrs)(idx(aa, 1))] as const;
            });
            return [ctorName, args] as const;
        });
}

function encodeConstructors<A>(encodeAttrs: Encoder<A>): Encoder<Constructors<A>> {
    return (ctors) =>
        ctors.map(([name, args]) => [
            encodeName(name),
            args.map(([argName, argType]) => [encodeName(argName), encodeType(encodeAttrs)(argType)]),
        ]);
}

// ---------------------------------------------------------------------------
// Pattern<A>
// ---------------------------------------------------------------------------

function decodePattern<A>(decodeAttrs: Decoder<A>): Decoder<Pattern<A>> {
    const lazy = (): Decoder<Pattern<A>> => (json) => decodePattern(decodeAttrs)(json);
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        switch (k) {
            case "WildcardPattern":
                return { kind: "WildcardPattern", attrs: decodeAttrs(idx(a, 1)) };
            case "AsPattern":
                return {
                    kind: "AsPattern",
                    attrs: decodeAttrs(idx(a, 1)),
                    pattern: lazy()(idx(a, 2)),
                    name: decodeName(idx(a, 3)),
                };
            case "TuplePattern":
                return { kind: "TuplePattern", attrs: decodeAttrs(idx(a, 1)), elements: arr(idx(a, 2)).map(lazy()) };
            case "ConstructorPattern":
                return {
                    kind: "ConstructorPattern",
                    attrs: decodeAttrs(idx(a, 1)),
                    name: decodeFQName(idx(a, 2)),
                    args: arr(idx(a, 3)).map(lazy()),
                };
            case "EmptyListPattern":
                return { kind: "EmptyListPattern", attrs: decodeAttrs(idx(a, 1)) };
            case "HeadTailPattern":
                return {
                    kind: "HeadTailPattern",
                    attrs: decodeAttrs(idx(a, 1)),
                    head: lazy()(idx(a, 2)),
                    tail: lazy()(idx(a, 3)),
                };
            case "LiteralPattern":
                return { kind: "LiteralPattern", attrs: decodeAttrs(idx(a, 1)), literal: decodeLiteral(idx(a, 2)) };
            case "UnitPattern":
                return { kind: "UnitPattern", attrs: decodeAttrs(idx(a, 1)) };
            default:
                throw new DecodeError(`Unknown Pattern kind: ${k}`);
        }
    };
}

function encodePattern<A>(encodeAttrs: Encoder<A>): Encoder<Pattern<A>> {
    const self = (): Encoder<Pattern<A>> => (v) => encodePattern(encodeAttrs)(v);
    return (p) => {
        switch (p.kind) {
            case "WildcardPattern": return ["WildcardPattern", encodeAttrs(p.attrs)];
            case "AsPattern": return ["AsPattern", encodeAttrs(p.attrs), self()(p.pattern), encodeName(p.name)];
            case "TuplePattern": return ["TuplePattern", encodeAttrs(p.attrs), p.elements.map(self())];
            case "ConstructorPattern": return ["ConstructorPattern", encodeAttrs(p.attrs), encodeFQName(p.name), p.args.map(self())];
            case "EmptyListPattern": return ["EmptyListPattern", encodeAttrs(p.attrs)];
            case "HeadTailPattern": return ["HeadTailPattern", encodeAttrs(p.attrs), self()(p.head), self()(p.tail)];
            case "LiteralPattern": return ["LiteralPattern", encodeAttrs(p.attrs), encodeLiteral(p.literal)];
            case "UnitPattern": return ["UnitPattern", encodeAttrs(p.attrs)];
        }
    };
}

// ---------------------------------------------------------------------------
// Value<TA,VA>
// ---------------------------------------------------------------------------

function decodeValueDefinition<TA, VA>(decodeTA: Decoder<TA>, decodeVA: Decoder<VA>): Decoder<ValueDefinition<TA, VA>> {
    return (json) => {
        const o = obj(json);
        return {
            inputTypes: arr(field(o, "inputTypes")).map((entry) => {
                const a = arr(entry);
                return [decodeName(idx(a, 0)), decodeVA(idx(a, 1)), decodeType(decodeTA)(idx(a, 2))] as const;
            }),
            outputType: decodeType(decodeTA)(field(o, "outputType")),
            body: decodeValue(decodeTA, decodeVA)(field(o, "body")),
        };
    };
}

function encodeValueDefinition<TA, VA>(encodeTA: Encoder<TA>, encodeVA: Encoder<VA>): Encoder<ValueDefinition<TA, VA>> {
    return (def) => ({
        inputTypes: def.inputTypes.map(([name, a, t]) => [encodeName(name), encodeVA(a), encodeType(encodeTA)(t)]),
        outputType: encodeType(encodeTA)(def.outputType),
        body: encodeValue(encodeTA, encodeVA)(def.body),
    });
}

function decodeValueSpecification<TA>(decodeTA: Decoder<TA>): Decoder<ValueSpecification<TA>> {
    return (json) => {
        const o = obj(json);
        return {
            inputs: arr(field(o, "inputs")).map((entry) => {
                const a = arr(entry);
                return [decodeName(idx(a, 0)), decodeType(decodeTA)(idx(a, 1))] as const;
            }),
            output: decodeType(decodeTA)(field(o, "output")),
        };
    };
}

function encodeValueSpecification<TA>(encodeTA: Encoder<TA>): Encoder<ValueSpecification<TA>> {
    return (spec) => ({
        inputs: spec.inputs.map(([name, t]) => [encodeName(name), encodeType(encodeTA)(t)]),
        output: encodeType(encodeTA)(spec.output),
    });
}

export function decodeValue<TA, VA>(decodeTA: Decoder<TA>, decodeVA: Decoder<VA>): Decoder<Value<TA, VA>> {
    const lazy = (): Decoder<Value<TA, VA>> => (json) => decodeValue(decodeTA, decodeVA)(json);
    const lazyPat = (): Decoder<Pattern<VA>> => (json) => decodePattern(decodeVA)(json);
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        switch (k) {
            case "Literal":
                return { kind: "Literal", attrs: decodeVA(idx(a, 1)), literal: decodeLiteral(idx(a, 2)) };
            case "Constructor":
                return { kind: "Constructor", attrs: decodeVA(idx(a, 1)), name: decodeFQName(idx(a, 2)) };
            case "Tuple":
                return { kind: "Tuple", attrs: decodeVA(idx(a, 1)), elements: arr(idx(a, 2)).map(lazy()) };
            case "List":
                return { kind: "List", attrs: decodeVA(idx(a, 1)), items: arr(idx(a, 2)).map(lazy()) };
            case "Record":
                return {
                    kind: "Record",
                    attrs: decodeVA(idx(a, 1)),
                    fields: arr(idx(a, 2)).map((entry) => {
                        const ea = arr(entry);
                        return [decodeName(idx(ea, 0)), lazy()(idx(ea, 1))] as const;
                    }),
                };
            case "Variable":
                return { kind: "Variable", attrs: decodeVA(idx(a, 1)), name: decodeName(idx(a, 2)) };
            case "Reference":
                return { kind: "Reference", attrs: decodeVA(idx(a, 1)), name: decodeFQName(idx(a, 2)) };
            case "Field":
                return {
                    kind: "Field",
                    attrs: decodeVA(idx(a, 1)),
                    subject: lazy()(idx(a, 2)),
                    fieldName: decodeName(idx(a, 3)),
                };
            case "FieldFunction":
                return { kind: "FieldFunction", attrs: decodeVA(idx(a, 1)), name: decodeName(idx(a, 2)) };
            case "Apply":
                return {
                    kind: "Apply",
                    attrs: decodeVA(idx(a, 1)),
                    function: lazy()(idx(a, 2)),
                    argument: lazy()(idx(a, 3)),
                };
            case "Lambda":
                return {
                    kind: "Lambda",
                    attrs: decodeVA(idx(a, 1)),
                    argumentPattern: lazyPat()(idx(a, 2)),
                    body: lazy()(idx(a, 3)),
                };
            case "LetDefinition":
                return {
                    kind: "LetDefinition",
                    attrs: decodeVA(idx(a, 1)),
                    name: decodeName(idx(a, 2)),
                    definition: decodeValueDefinition(decodeTA, decodeVA)(idx(a, 3)),
                    inValue: lazy()(idx(a, 4)),
                };
            case "LetRecursion":
                return {
                    kind: "LetRecursion",
                    attrs: decodeVA(idx(a, 1)),
                    definitions: arr(idx(a, 2)).map((entry) => {
                        const ea = arr(entry);
                        return [
                            decodeName(idx(ea, 0)),
                            decodeValueDefinition(decodeTA, decodeVA)(idx(ea, 1)),
                        ] as const;
                    }),
                    inValue: lazy()(idx(a, 3)),
                };
            case "Destructure":
                return {
                    kind: "Destructure",
                    attrs: decodeVA(idx(a, 1)),
                    pattern: lazyPat()(idx(a, 2)),
                    valueToDestruct: lazy()(idx(a, 3)),
                    inValue: lazy()(idx(a, 4)),
                };
            case "IfThenElse":
                return {
                    kind: "IfThenElse",
                    attrs: decodeVA(idx(a, 1)),
                    condition: lazy()(idx(a, 2)),
                    thenBranch: lazy()(idx(a, 3)),
                    elseBranch: lazy()(idx(a, 4)),
                };
            case "PatternMatch":
                return {
                    kind: "PatternMatch",
                    attrs: decodeVA(idx(a, 1)),
                    subject: lazy()(idx(a, 2)),
                    cases: arr(idx(a, 3)).map((entry) => {
                        const ea = arr(entry);
                        return [lazyPat()(idx(ea, 0)), lazy()(idx(ea, 1))] as const;
                    }),
                };
            case "UpdateRecord":
                return {
                    kind: "UpdateRecord",
                    attrs: decodeVA(idx(a, 1)),
                    subject: lazy()(idx(a, 2)),
                    fields: arr(idx(a, 3)).map((entry) => {
                        const ea = arr(entry);
                        return [decodeName(idx(ea, 0)), lazy()(idx(ea, 1))] as const;
                    }),
                };
            case "Unit":
                return { kind: "Unit", attrs: decodeVA(idx(a, 1)) };
            default:
                throw new DecodeError(`Unknown Value kind: ${k}`);
        }
    };
}

export function encodeValue<TA, VA>(encodeTA: Encoder<TA>, encodeVA: Encoder<VA>): Encoder<Value<TA, VA>> {
    const self = (): Encoder<Value<TA, VA>> => (v) => encodeValue(encodeTA, encodeVA)(v);
    const selfPat = (): Encoder<Pattern<VA>> => (p) => encodePattern(encodeVA)(p);
    return (v) => {
        switch (v.kind) {
            case "Literal": return ["Literal", encodeVA(v.attrs), encodeLiteral(v.literal)];
            case "Constructor": return ["Constructor", encodeVA(v.attrs), encodeFQName(v.name)];
            case "Tuple": return ["Tuple", encodeVA(v.attrs), v.elements.map(self())];
            case "List": return ["List", encodeVA(v.attrs), v.items.map(self())];
            case "Record":
                return ["Record", encodeVA(v.attrs), v.fields.map(([n, val]) => [encodeName(n), self()(val)])];
            case "Variable": return ["Variable", encodeVA(v.attrs), encodeName(v.name)];
            case "Reference": return ["Reference", encodeVA(v.attrs), encodeFQName(v.name)];
            case "Field": return ["Field", encodeVA(v.attrs), self()(v.subject), encodeName(v.fieldName)];
            case "FieldFunction": return ["FieldFunction", encodeVA(v.attrs), encodeName(v.name)];
            case "Apply": return ["Apply", encodeVA(v.attrs), self()(v.function), self()(v.argument)];
            case "Lambda":
                return ["Lambda", encodeVA(v.attrs), selfPat()(v.argumentPattern), self()(v.body)];
            case "LetDefinition":
                return [
                    "LetDefinition", encodeVA(v.attrs), encodeName(v.name),
                    encodeValueDefinition(encodeTA, encodeVA)(v.definition), self()(v.inValue),
                ];
            case "LetRecursion":
                return [
                    "LetRecursion", encodeVA(v.attrs),
                    v.definitions.map(([n, d]) => [encodeName(n), encodeValueDefinition(encodeTA, encodeVA)(d)]),
                    self()(v.inValue),
                ];
            case "Destructure":
                return [
                    "Destructure", encodeVA(v.attrs), selfPat()(v.pattern),
                    self()(v.valueToDestruct), self()(v.inValue),
                ];
            case "IfThenElse":
                return [
                    "IfThenElse", encodeVA(v.attrs), self()(v.condition),
                    self()(v.thenBranch), self()(v.elseBranch),
                ];
            case "PatternMatch":
                return [
                    "PatternMatch", encodeVA(v.attrs), self()(v.subject),
                    v.cases.map(([p, body]) => [selfPat()(p), self()(body)]),
                ];
            case "UpdateRecord":
                return [
                    "UpdateRecord", encodeVA(v.attrs), self()(v.subject),
                    v.fields.map(([n, val]) => [encodeName(n), self()(val)]),
                ];
            case "Unit": return ["Unit", encodeVA(v.attrs)];
        }
    };
}

// ---------------------------------------------------------------------------
// Module
// ---------------------------------------------------------------------------

function decodeModuleDefinition<TA, VA>(decodeTA: Decoder<TA>, decodeVA: Decoder<VA>): Decoder<ModuleDefinition<TA, VA>> {
    return (json) => {
        const o = obj(json);
        return {
            types: arr(field(o, "types")).map((entry) => {
                const a = arr(entry);
                return [
                    decodeName(idx(a, 0)),
                    decodeAccessControlled(decodeDocumented(decodeTypeDefinition(decodeTA)))(idx(a, 1)),
                ] as const;
            }),
            values: arr(field(o, "values")).map((entry) => {
                const a = arr(entry);
                return [
                    decodeName(idx(a, 0)),
                    decodeAccessControlled(decodeDocumented(decodeValueDefinition(decodeTA, decodeVA)))(idx(a, 1)),
                ] as const;
            }),
            doc: (optField(o, "doc") as string | null | undefined) ?? null,
        };
    };
}

function encodeModuleDefinition<TA, VA>(encodeTA: Encoder<TA>, encodeVA: Encoder<VA>): Encoder<ModuleDefinition<TA, VA>> {
    return (def) => ({
        types: def.types.map(([name, typeDef]) => [
            encodeName(name),
            encodeAccessControlled(encodeDocumented(encodeTypeDefinition(encodeTA)))(typeDef),
        ]),
        values: def.values.map(([name, valueDef]) => [
            encodeName(name),
            encodeAccessControlled(encodeDocumented(encodeValueDefinition(encodeTA, encodeVA)))(valueDef),
        ]),
        doc: def.doc ?? null,
    });
}

function decodeModuleSpecification<TA>(decodeTA: Decoder<TA>): Decoder<ModuleSpecification<TA>> {
    return (json) => {
        const o = obj(json);
        return {
            types: arr(field(o, "types")).map((entry) => {
                const a = arr(entry);
                return [
                    decodeName(idx(a, 0)),
                    decodeDocumented(decodeTypeSpecification(decodeTA))(idx(a, 1)),
                ] as const;
            }),
            values: arr(field(o, "values")).map((entry) => {
                const a = arr(entry);
                return [
                    decodeName(idx(a, 0)),
                    decodeDocumented(decodeValueSpecification(decodeTA))(idx(a, 1)),
                ] as const;
            }),
            doc: (optField(o, "doc") as string | null | undefined) ?? null,
        };
    };
}

function encodeModuleSpecification<TA>(encodeTA: Encoder<TA>): Encoder<ModuleSpecification<TA>> {
    return (spec) => ({
        types: spec.types.map(([name, typeSpec]) => [encodeName(name), encodeDocumented(encodeTypeSpecification(encodeTA))(typeSpec)]),
        values: spec.values.map(([name, valueSpec]) => [encodeName(name), encodeDocumented(encodeValueSpecification(encodeTA))(valueSpec)]),
        doc: spec.doc ?? null,
    });
}

// ---------------------------------------------------------------------------
// Package
// ---------------------------------------------------------------------------

function decodePackageDefinition<TA, VA>(decodeTA: Decoder<TA>, decodeVA: Decoder<VA>): Decoder<PackageDefinition<TA, VA>> {
    return (json) => {
        const o = obj(json);
        return {
            modules: arr(field(o, "modules")).map((entry) => {
                const a = arr(entry);
                return [
                    decodePath(idx(a, 0)),
                    decodeAccessControlled(decodeModuleDefinition(decodeTA, decodeVA))(idx(a, 1)),
                ] as const;
            }),
        };
    };
}

function encodePackageDefinition<TA, VA>(encodeTA: Encoder<TA>, encodeVA: Encoder<VA>): Encoder<PackageDefinition<TA, VA>> {
    return (def) => ({
        modules: def.modules.map(([path, moduleDef]) => [
            encodePath(path),
            encodeAccessControlled(encodeModuleDefinition(encodeTA, encodeVA))(moduleDef),
        ]),
    });
}

function decodePackageSpecification<TA>(decodeTA: Decoder<TA>): Decoder<PackageSpecification<TA>> {
    return (json) => {
        const o = obj(json);
        return {
            modules: arr(field(o, "modules")).map((entry) => {
                const a = arr(entry);
                return [decodePath(idx(a, 0)), decodeModuleSpecification(decodeTA)(idx(a, 1))] as const;
            }),
        };
    };
}

function encodePackageSpecification<TA>(encodeTA: Encoder<TA>): Encoder<PackageSpecification<TA>> {
    return (spec) => ({
        modules: spec.modules.map(([path, moduleSpec]) => [encodePath(path), encodeModuleSpecification(encodeTA)(moduleSpec)]),
    });
}

// ---------------------------------------------------------------------------
// Distribution
// ---------------------------------------------------------------------------

/**
 * Decode a raw (unversioned) distribution array:
 * `["Library", packagePath, deps, packageDef]`
 */
export function decodeDistribution<TA, VA>(decodeTA: Decoder<TA>, decodeVA: Decoder<VA>): Decoder<Distribution<TA, VA>> {
    return (json) => {
        const a = arr(json);
        const k = tag(a);
        if (k !== "Library") throw new DecodeError(`Unknown Distribution kind: ${k}`);
        return {
            kind: "Library",
            packageName: decodePath(idx(a, 1)),
            dependencies: arr(idx(a, 2)).map((entry) => {
                const ea = arr(entry);
                return [decodePath(idx(ea, 0)), decodePackageSpecification(decodeTA)(idx(ea, 1))] as const;
            }),
            packageDef: decodePackageDefinition(decodeTA, decodeVA)(idx(a, 3)),
        };
    };
}

/**
 * Encode a distribution to a raw array (without version wrapper).
 */
export function encodeDistribution<TA, VA>(encodeTA: Encoder<TA>, encodeVA: Encoder<VA>): Encoder<Distribution<TA, VA>> {
    return (dist) => [
        "Library",
        encodePath(dist.packageName),
        dist.dependencies.map(([path, spec]) => [encodePath(path), encodePackageSpecification(encodeTA)(spec)]),
        encodePackageDefinition(encodeTA, encodeVA)(dist.packageDef),
    ];
}

// ---------------------------------------------------------------------------
// Versioned top-level (formatVersion 3)
// ---------------------------------------------------------------------------

const CURRENT_FORMAT_VERSION = 3;

/**
 * Decode a versioned `morphir.json` file:
 * `{ "formatVersion": 3, "distribution": [...] }`
 */
export function decodeVersionedDistribution<TA, VA>(
    decodeTA: Decoder<TA>,
    decodeVA: Decoder<VA>,
): Decoder<Distribution<TA, VA>> {
    return (json) => {
        const o = obj(json);
        const version = num(field(o, "formatVersion"));
        if (version !== CURRENT_FORMAT_VERSION) {
            throw new DecodeError(
                `Unsupported formatVersion ${version}; expected ${CURRENT_FORMAT_VERSION}`,
            );
        }
        return decodeDistribution(decodeTA, decodeVA)(field(o, "distribution"));
    };
}

/**
 * Encode a distribution to the versioned top-level object.
 */
export function encodeVersionedDistribution<TA, VA>(
    encodeTA: Encoder<TA>,
    encodeVA: Encoder<VA>,
): Encoder<Distribution<TA, VA>> {
    return (dist) => ({
        formatVersion: CURRENT_FORMAT_VERSION,
        distribution: encodeDistribution(encodeTA, encodeVA)(dist),
    });
}

// ---------------------------------------------------------------------------
// Substrate-flavoured helpers
// ---------------------------------------------------------------------------

/**
 * Decode the empty `{}` attribute that morphir-elm emits for type nodes today.
 * Tolerates `null`/absent for forward-compat.
 */
export function decodeTypeAttrs(json: unknown): TypeAttrs {
    if (json !== null && typeof json === "object" && !Array.isArray(json)) {
        const o = json as Record<string, unknown>;
        if ("src" in o && o["src"] !== null && o["src"] !== undefined) {
            const src = o["src"] as { file: string; sectionId: string; text: string };
            return { src };
        }
    }
    return {};
}

/**
 * Decode the value attribute.  Today morphir-elm emits a `Type<{}>` expression
 * directly in the `va` slot (e.g. `["Unit", {}]`).  In the future it will emit
 * `{ "src": ..., "type": ... }`.  This function is the **single edit point**
 * for that transition.
 */
export function decodeValueAttrs(json: unknown): ValueAttrs {
    if (Array.isArray(json)) {
        // current morphir-elm: va slot is a bare Type<{}> expression
        const type = decodeType(decodeTypeAttrs)(json);
        return { type };
    }
    if (json !== null && typeof json === "object" && !Array.isArray(json)) {
        const o = json as Record<string, unknown>;
        if ("type" in o) {
            // future morphir-elm: { src?: ..., type: <Type> }
            const type = decodeType(decodeTypeAttrs)(o["type"]);
            const src = o["src"] as { file: string; sectionId: string; text: string } | undefined;
            return src ? { type, src } : { type };
        }
    }
    // fallback for null / {} (morphir-elm emitting unit)
    return { type: { kind: "Unit", attrs: {} } };
}

export function encodeTypeAttrs(attrs: TypeAttrs): unknown {
    if (attrs.src) return { src: attrs.src };
    return {};
}

export function encodeValueAttrs(attrs: ValueAttrs): unknown {
    const typeJson = encodeType(encodeTypeAttrs)(attrs.type);
    if (attrs.src) return { src: attrs.src, type: typeJson };
    return typeJson;
}

/** Decode a `morphir.json` file into a `SubstrateDistribution`. */
export function decodeSubstrateDistribution(json: unknown): SubstrateDistribution {
    return decodeVersionedDistribution(decodeTypeAttrs, decodeValueAttrs)(json);
}

/** Encode a `SubstrateDistribution` to the versioned JSON object. */
export function encodeSubstrateDistribution(dist: SubstrateDistribution): unknown {
    return encodeVersionedDistribution(encodeTypeAttrs, encodeValueAttrs)(dist);
}

// ---------------------------------------------------------------------------
// Result-based wrappers
// ---------------------------------------------------------------------------

export type DecodeResult<T> =
    | { readonly ok: true; readonly value: T }
    | { readonly ok: false; readonly error: DecodeError };

/**
 * Result-based wrapper around `decodeSubstrateDistribution`.
 * Catches `DecodeError` and wraps it in a `{ ok: false, error }` object so
 * callers don't need try/catch.
 */
export function tryDecodeSubstrateDistribution(
    json: unknown,
): DecodeResult<SubstrateDistribution> {
    try {
        return { ok: true, value: decodeSubstrateDistribution(json) };
    } catch (e) {
        if (e instanceof DecodeError) return { ok: false, error: e };
        return { ok: false, error: new DecodeError(String(e)) };
    }
}

/**
 * Result-based wrapper around `decodeVersionedDistribution`.
 */
export function tryDecodeVersionedDistribution<TA, VA>(
    json: unknown,
    decodeTA: (j: unknown) => TA,
    decodeVA: (j: unknown) => VA,
): DecodeResult<Distribution<TA, VA>> {
    try {
        return { ok: true, value: decodeVersionedDistribution(decodeTA, decodeVA)(json) };
    } catch (e) {
        if (e instanceof DecodeError) return { ok: false, error: e };
        return { ok: false, error: new DecodeError(String(e)) };
    }
}
