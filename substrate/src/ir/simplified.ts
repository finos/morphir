/**
 * Decoder for the **Simplified Morphir IR** — the per-module JSON format
 * produced by `morphir simplify`.  See morphir-elm/docs/simplified-ir-format.md
 * for the full specification.
 *
 * The simplified format throws away inferred attributes (no `ta` / `va`
 * payloads), uses TitleCase strings for names and `"Pkg.Path:Mod.Path:local"`
 * triples for FQNames, and collapses curried `Apply` chains.  This file
 * inflates that back into the canonical `Distribution<TypeAttrs, ValueAttrs>`
 * shape used everywhere else in substrate.
 *
 * The output is a `SubstrateDistribution` — type-level attributes are
 * filled with `{}` and value-level attributes with a placeholder
 * `Unit` inferred type, because the simplified format doesn't carry them.
 */

import type {
    AccessControlled,
    Constructors,
    Distribution,
    Documented,
    Field,
    FQName,
    Literal,
    ModuleDefinition,
    Name,
    PackageDefinition,
    Path,
    Pattern,
    Type,
    TypeDefinition,
    Value,
    ValueDefinition,
} from "./distribution.js";

import type { TypeAttrs, ValueAttrs, SubstrateDistribution } from "./attrs.js";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

export class SimplifiedDecodeError extends Error {
    constructor(message: string, public readonly path: (string | number)[] = []) {
        super(`${message}${path.length ? ` at ${path.join(".")}` : ""}`);
        this.name = "SimplifiedDecodeError";
    }
}

function fail(msg: string, path: (string | number)[] = []): never {
    throw new SimplifiedDecodeError(msg, path);
}

// ---------------------------------------------------------------------------
// Name / Path / FQName decoding
// ---------------------------------------------------------------------------

/**
 * Split a TitleCase or camelCase identifier into its constituent words,
 * lowercased.  Each uppercase letter starts a new word; digits and
 * lowercase letters stay attached to the current word.
 *
 *   "ProductID"   → ["product", "i", "d"]
 *   "productID"   → ["product", "i", "d"]
 *   "padLeft"     → ["pad", "left"]
 *   "SDK"         → ["s", "d", "k"]
 *   "Issue210"    → ["issue210"]
 */
export function nameFromCased(s: string): Name {
    if (s.length === 0) return [];
    const words: string[] = [];
    let cur = "";
    for (const c of s) {
        const isUpper = c >= "A" && c <= "Z";
        if (cur === "") {
            cur = c.toLowerCase();
        } else if (isUpper) {
            words.push(cur);
            cur = c.toLowerCase();
        } else {
            cur += c;
        }
    }
    if (cur) words.push(cur);
    return words;
}

/** Split a dot-separated dotted path (e.g. "Morphir.SDK") into a `Path`. */
export function pathFromDotted(s: string): Path {
    if (s.length === 0) return [];
    return s.split(".").map(nameFromCased);
}

/** Parse `"Pkg.Path:Mod.Path:local"` into an `FQName`. */
export function fqnFromString(s: string): FQName {
    const parts = s.split(":");
    if (parts.length !== 3) fail(`Invalid FQName "${s}" — expected 3 colon-separated segments`);
    return [pathFromDotted(parts[0]!), pathFromDotted(parts[1]!), nameFromCased(parts[2]!)];
}

// ---------------------------------------------------------------------------
// Attribute helpers
// ---------------------------------------------------------------------------

const TYPE_ATTRS: TypeAttrs = {};
const UNIT_TYPE: Type<{}> = { kind: "Unit", attrs: {} };
const VALUE_ATTRS: ValueAttrs = { type: UNIT_TYPE };

// ---------------------------------------------------------------------------
// Type expressions
// ---------------------------------------------------------------------------

export function decodeType(json: unknown, path: (string | number)[] = []): Type<TypeAttrs> {
    if (json === "Unit") return { kind: "Unit", attrs: TYPE_ATTRS };
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail(`Expected type expression, got ${typeof json}`, path);
    }
    const o = json as Record<string, unknown>;
    const keys = Object.keys(o);
    if (keys.length !== 1) fail(`Type expression must have exactly one tag key, got ${keys.join(",")}`, path);
    const tag = keys[0]!;
    const v = o[tag];
    switch (tag) {
        case "Variable":
            if (typeof v !== "string") fail("Variable expects a string", [...path, tag]);
            return { kind: "Variable", attrs: TYPE_ATTRS, name: nameFromCased(v) };
        case "Reference": {
            // Bare string = no args; object form = { name, params }
            if (typeof v === "string") {
                return { kind: "Reference", attrs: TYPE_ATTRS, name: fqnFromString(v), typeParams: [] };
            }
            if (typeof v !== "object" || v === null) fail("Reference expects string or object", [...path, tag]);
            const ro = v as Record<string, unknown>;
            const name = ro["name"];
            const params = ro["params"];
            if (typeof name !== "string") fail("Reference.name must be string", [...path, tag, "name"]);
            const ps = Array.isArray(params) ? params : [];
            return {
                kind: "Reference",
                attrs: TYPE_ATTRS,
                name: fqnFromString(name),
                typeParams: ps.map((p, i) => decodeType(p, [...path, tag, "params", i])),
            };
        }
        case "Tuple": {
            if (!Array.isArray(v)) fail("Tuple expects an array", [...path, tag]);
            return {
                kind: "Tuple",
                attrs: TYPE_ATTRS,
                elements: v.map((e, i) => decodeType(e, [...path, tag, i])),
            };
        }
        case "Record": {
            if (typeof v !== "object" || v === null || Array.isArray(v)) fail("Record expects an object", [...path, tag]);
            const fields: Field<TypeAttrs>[] = [];
            for (const [k, fv] of Object.entries(v as Record<string, unknown>)) {
                fields.push({ name: nameFromCased(k), tpe: decodeType(fv, [...path, tag, k]) });
            }
            return { kind: "Record", attrs: TYPE_ATTRS, fields };
        }
        case "ExtensibleRecord": {
            if (typeof v !== "object" || v === null || Array.isArray(v)) fail("ExtensibleRecord expects an object", [...path, tag]);
            const eo = v as Record<string, unknown>;
            const varName = eo["variable"];
            if (typeof varName !== "string") fail("ExtensibleRecord.variable must be string", [...path, tag]);
            const fields: Field<TypeAttrs>[] = [];
            for (const [k, fv] of Object.entries(eo)) {
                if (k === "variable") continue;
                fields.push({ name: nameFromCased(k), tpe: decodeType(fv, [...path, tag, k]) });
            }
            return { kind: "ExtensibleRecord", attrs: TYPE_ATTRS, name: nameFromCased(varName), fields };
        }
        case "Function": {
            if (typeof v !== "object" || v === null || Array.isArray(v)) fail("Function expects an object", [...path, tag]);
            const fo = v as Record<string, unknown>;
            return {
                kind: "Function",
                attrs: TYPE_ATTRS,
                argumentType: decodeType(fo["from"], [...path, tag, "from"]),
                returnType: decodeType(fo["to"], [...path, tag, "to"]),
            };
        }
        default:
            fail(`Unknown type tag "${tag}"`, path);
    }
}

// ---------------------------------------------------------------------------
// Type definitions (Alias / Union)
// ---------------------------------------------------------------------------

function decodeTypeDefinition(json: unknown, path: (string | number)[] = []): Documented<TypeDefinition<TypeAttrs>> {
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail(`Type definition must be an object`, path);
    }
    const o = json as Record<string, unknown>;
    if ("Alias" in o) {
        return decodeAlias(o["Alias"], [...path, "Alias"]);
    }
    if ("Union" in o) {
        return decodeUnion(o["Union"], [...path, "Union"]);
    }
    fail(`Type definition must have "Alias" or "Union" key, got ${Object.keys(o).join(",")}`, path);
}

function decodeAlias(json: unknown, path: (string | number)[]): Documented<TypeDefinition<TypeAttrs>> {
    // Expanded form: { doc?, params?, type }  ;  collapsed form: <TypeExpr>
    const isExpanded =
        typeof json === "object" && json !== null && !Array.isArray(json) &&
        "type" in (json as Record<string, unknown>);
    if (isExpanded) {
        const o = json as Record<string, unknown>;
        const params = Array.isArray(o["params"]) ? (o["params"] as unknown[]).map((p) => {
            if (typeof p !== "string") fail("Alias params entry must be string", path);
            return nameFromCased(p);
        }) : [];
        const doc = typeof o["doc"] === "string" ? (o["doc"] as string) : "";
        const expr = decodeType(o["type"], [...path, "type"]);
        return { doc, value: { kind: "TypeAliasDefinition", params, expr } };
    }
    return { doc: "", value: { kind: "TypeAliasDefinition", params: [], expr: decodeType(json, path) } };
}

function decodeUnion(json: unknown, path: (string | number)[]): Documented<TypeDefinition<TypeAttrs>> {
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail("Union expects an object", path);
    }
    const o = json as Record<string, unknown>;
    const isExpanded = "constructors" in o;
    const params: Name[] = [];
    let doc = "";
    let ctorsObj: Record<string, unknown>;
    if (isExpanded) {
        if (Array.isArray(o["params"])) {
            for (const p of o["params"] as unknown[]) {
                if (typeof p !== "string") fail("Union params entry must be string", path);
                params.push(nameFromCased(p));
            }
        }
        if (typeof o["doc"] === "string") doc = o["doc"] as string;
        const c = o["constructors"];
        if (typeof c !== "object" || c === null || Array.isArray(c)) fail("Union.constructors must be an object", path);
        ctorsObj = c as Record<string, unknown>;
    } else {
        ctorsObj = o;
    }
    const constructors: Constructors<TypeAttrs> = Object.entries(ctorsObj).map(([ctorName, argsJson]) => {
        if (typeof argsJson !== "object" || argsJson === null || Array.isArray(argsJson)) {
            fail(`Constructor ${ctorName} must map to an object of args`, path);
        }
        const args: ReadonlyArray<readonly [Name, Type<TypeAttrs>]> = Object.entries(argsJson as Record<string, unknown>)
            .map(([argName, argType]) => [nameFromCased(argName), decodeType(argType, [...path, ctorName, argName])] as const);
        return [nameFromCased(ctorName), args] as const;
    });
    return {
        doc,
        value: {
            kind: "CustomTypeDefinition",
            params,
            constructors: { access: "Public", value: constructors },
        },
    };
}

// ---------------------------------------------------------------------------
// Literals
// ---------------------------------------------------------------------------

function decodeLiteral(o: Record<string, unknown>): Literal | null {
    if ("Bool" in o) return { kind: "BoolLiteral", value: Boolean(o["Bool"]) };
    if ("Char" in o) return { kind: "CharLiteral", value: String(o["Char"]) };
    if ("String" in o) return { kind: "StringLiteral", value: String(o["String"]) };
    if ("Int" in o) return { kind: "WholeNumberLiteral", value: Number(o["Int"]) };
    if ("Float" in o) return { kind: "FloatLiteral", value: Number(o["Float"]) };
    if ("Decimal" in o) return { kind: "DecimalLiteral", value: String(o["Decimal"]) };
    return null;
}

// ---------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------

export function decodePattern(json: unknown, path: (string | number)[] = []): Pattern<ValueAttrs> {
    if (json === "_") return { kind: "WildcardPattern", attrs: VALUE_ATTRS };
    if (json === "[]") return { kind: "EmptyListPattern", attrs: VALUE_ATTRS };
    if (json === "()") return { kind: "UnitPattern", attrs: VALUE_ATTRS };
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail(`Pattern must be a tag string or object, got ${typeof json}`, path);
    }
    const o = json as Record<string, unknown>;
    if ("As" in o) {
        const v = o["As"];
        if (typeof v === "string") {
            return {
                kind: "AsPattern",
                attrs: VALUE_ATTRS,
                pattern: { kind: "WildcardPattern", attrs: VALUE_ATTRS },
                name: nameFromCased(v),
            };
        }
        if (typeof v === "object" && v !== null) {
            const ao = v as Record<string, unknown>;
            const inner = decodePattern(ao["pattern"], [...path, "As", "pattern"]);
            const name = ao["name"];
            if (typeof name !== "string") fail("As.name must be string", [...path, "As"]);
            return { kind: "AsPattern", attrs: VALUE_ATTRS, pattern: inner, name: nameFromCased(name) };
        }
        fail("As pattern expects string or {pattern,name}", [...path, "As"]);
    }
    if ("Tuple" in o) {
        const v = o["Tuple"];
        if (!Array.isArray(v)) fail("Tuple pattern expects array", [...path, "Tuple"]);
        return {
            kind: "TuplePattern",
            attrs: VALUE_ATTRS,
            elements: v.map((e, i) => decodePattern(e, [...path, "Tuple", i])),
        };
    }
    if ("Ctor" in o) {
        const v = o["Ctor"];
        if (typeof v === "string") {
            return { kind: "ConstructorPattern", attrs: VALUE_ATTRS, name: fqnFromString(v), args: [] };
        }
        if (typeof v === "object" && v !== null) {
            const entries = Object.entries(v as Record<string, unknown>);
            if (entries.length !== 1) fail("Ctor pattern object must have one key", [...path, "Ctor"]);
            const [fqn, args] = entries[0]!;
            if (!Array.isArray(args)) fail("Ctor args must be an array", [...path, "Ctor", fqn]);
            return {
                kind: "ConstructorPattern",
                attrs: VALUE_ATTRS,
                name: fqnFromString(fqn),
                args: args.map((a, i) => decodePattern(a, [...path, "Ctor", fqn, i])),
            };
        }
        fail("Ctor pattern expects string or object", [...path, "Ctor"]);
    }
    if ("HeadTail" in o) {
        const v = o["HeadTail"];
        if (typeof v !== "object" || v === null) fail("HeadTail expects object", [...path, "HeadTail"]);
        const ho = v as Record<string, unknown>;
        return {
            kind: "HeadTailPattern",
            attrs: VALUE_ATTRS,
            head: decodePattern(ho["head"], [...path, "HeadTail", "head"]),
            tail: decodePattern(ho["tail"], [...path, "HeadTail", "tail"]),
        };
    }
    if ("Literal" in o) {
        const lit = decodeLiteral(o["Literal"] as Record<string, unknown>);
        if (!lit) fail("Unknown literal pattern", [...path, "Literal"]);
        return { kind: "LiteralPattern", attrs: VALUE_ATTRS, literal: lit };
    }
    fail(`Unknown pattern tag(s) ${Object.keys(o).join(",")}`, path);
}

// ---------------------------------------------------------------------------
// Value expressions
// ---------------------------------------------------------------------------

export function decodeValue(json: unknown, path: (string | number)[] = []): Value<TypeAttrs, ValueAttrs> {
    if (json === "Unit") return { kind: "Unit", attrs: VALUE_ATTRS };
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail(`Value expression must be object or "Unit", got ${typeof json}`, path);
    }
    const o = json as Record<string, unknown>;

    // Literals
    const lit = decodeLiteral(o);
    if (lit) return { kind: "Literal", attrs: VALUE_ATTRS, literal: lit };

    if ("Variable" in o) {
        const v = o["Variable"];
        if (typeof v !== "string") fail("Variable expects string", [...path, "Variable"]);
        return { kind: "Variable", attrs: VALUE_ATTRS, name: nameFromCased(v) };
    }
    if ("Reference" in o) {
        const v = o["Reference"];
        if (typeof v !== "string") fail("Value Reference expects string", [...path, "Reference"]);
        return { kind: "Reference", attrs: VALUE_ATTRS, name: fqnFromString(v) };
    }
    if ("Constructor" in o) {
        const v = o["Constructor"];
        if (typeof v !== "string") fail("Constructor expects string", [...path, "Constructor"]);
        return { kind: "Constructor", attrs: VALUE_ATTRS, name: fqnFromString(v) };
    }
    if ("Tuple" in o) {
        const v = o["Tuple"];
        if (!Array.isArray(v)) fail("Tuple expects array", [...path, "Tuple"]);
        return { kind: "Tuple", attrs: VALUE_ATTRS, elements: v.map((e, i) => decodeValue(e, [...path, "Tuple", i])) };
    }
    if ("List" in o) {
        const v = o["List"];
        if (!Array.isArray(v)) fail("List expects array", [...path, "List"]);
        return { kind: "List", attrs: VALUE_ATTRS, items: v.map((e, i) => decodeValue(e, [...path, "List", i])) };
    }
    if ("Record" in o) {
        const v = o["Record"];
        if (typeof v !== "object" || v === null || Array.isArray(v)) fail("Record expects object", [...path, "Record"]);
        const fields: ReadonlyArray<readonly [Name, Value<TypeAttrs, ValueAttrs>]> =
            Object.entries(v as Record<string, unknown>).map(([k, fv]) =>
                [nameFromCased(k), decodeValue(fv, [...path, "Record", k])] as const);
        return { kind: "Record", attrs: VALUE_ATTRS, fields };
    }
    if ("Field" in o) {
        const v = o["Field"];
        if (typeof v !== "object" || v === null) fail("Field expects object", [...path, "Field"]);
        const fo = v as Record<string, unknown>;
        const fieldName = fo["field"];
        if (typeof fieldName !== "string") fail("Field.field must be string", [...path, "Field"]);
        return {
            kind: "Field",
            attrs: VALUE_ATTRS,
            subject: decodeValue(fo["on"], [...path, "Field", "on"]),
            fieldName: nameFromCased(fieldName),
        };
    }
    if ("FieldFunction" in o) {
        const v = o["FieldFunction"];
        if (typeof v !== "string") fail("FieldFunction expects string", [...path, "FieldFunction"]);
        return { kind: "FieldFunction", attrs: VALUE_ATTRS, name: nameFromCased(v) };
    }
    if ("Apply" in o) {
        const v = o["Apply"];
        if (!Array.isArray(v) || v.length < 1) fail("Apply expects non-empty array", [...path, "Apply"]);
        // Fold curried form: [f, a, b, c] → Apply(Apply(Apply(f, a), b), c).
        let cur: Value<TypeAttrs, ValueAttrs> = decodeValue(v[0], [...path, "Apply", 0]);
        for (let i = 1; i < v.length; i++) {
            cur = {
                kind: "Apply",
                attrs: VALUE_ATTRS,
                function: cur,
                argument: decodeValue(v[i], [...path, "Apply", i]),
            };
        }
        return cur;
    }
    if ("Lambda" in o) {
        const v = o["Lambda"];
        if (typeof v !== "object" || v === null) fail("Lambda expects object", [...path, "Lambda"]);
        const lo = v as Record<string, unknown>;
        return {
            kind: "Lambda",
            attrs: VALUE_ATTRS,
            argumentPattern: decodePattern(lo["arg"], [...path, "Lambda", "arg"]),
            body: decodeValue(lo["body"], [...path, "Lambda", "body"]),
        };
    }
    if ("Let" in o) {
        const v = o["Let"];
        if (typeof v !== "object" || v === null) fail("Let expects object", [...path, "Let"]);
        const lo = v as Record<string, unknown>;
        const name = lo["name"];
        if (typeof name !== "string") fail("Let.name must be string", [...path, "Let"]);
        return {
            kind: "LetDefinition",
            attrs: VALUE_ATTRS,
            name: nameFromCased(name),
            definition: decodeValueDefinition(lo["def"], [...path, "Let", "def"]),
            inValue: decodeValue(lo["in"], [...path, "Let", "in"]),
        };
    }
    if ("LetRec" in o) {
        const v = o["LetRec"];
        if (typeof v !== "object" || v === null) fail("LetRec expects object", [...path, "LetRec"]);
        const lo = v as Record<string, unknown>;
        const defsObj = lo["defs"];
        if (typeof defsObj !== "object" || defsObj === null || Array.isArray(defsObj)) {
            fail("LetRec.defs must be an object", [...path, "LetRec", "defs"]);
        }
        const definitions: ReadonlyArray<readonly [Name, ValueDefinition<TypeAttrs, ValueAttrs>]> =
            Object.entries(defsObj as Record<string, unknown>).map(([n, def]) =>
                [nameFromCased(n), decodeValueDefinition(def, [...path, "LetRec", "defs", n])] as const);
        return {
            kind: "LetRecursion",
            attrs: VALUE_ATTRS,
            definitions,
            inValue: decodeValue(lo["in"], [...path, "LetRec", "in"]),
        };
    }
    if ("Destructure" in o) {
        const v = o["Destructure"];
        if (typeof v !== "object" || v === null) fail("Destructure expects object", [...path, "Destructure"]);
        const dop = v as Record<string, unknown>;
        return {
            kind: "Destructure",
            attrs: VALUE_ATTRS,
            pattern: decodePattern(dop["pattern"], [...path, "Destructure", "pattern"]),
            valueToDestruct: decodeValue(dop["value"], [...path, "Destructure", "value"]),
            inValue: decodeValue(dop["in"], [...path, "Destructure", "in"]),
        };
    }
    if ("If" in o) {
        const v = o["If"];
        if (typeof v !== "object" || v === null) fail("If expects object", [...path, "If"]);
        const io = v as Record<string, unknown>;
        return {
            kind: "IfThenElse",
            attrs: VALUE_ATTRS,
            condition: decodeValue(io["cond"], [...path, "If", "cond"]),
            thenBranch: decodeValue(io["then"], [...path, "If", "then"]),
            elseBranch: decodeValue(io["else"], [...path, "If", "else"]),
        };
    }
    if ("Match" in o) {
        const v = o["Match"];
        if (typeof v !== "object" || v === null) fail("Match expects object", [...path, "Match"]);
        const mo = v as Record<string, unknown>;
        const cases = mo["cases"];
        if (!Array.isArray(cases)) fail("Match.cases must be array", [...path, "Match", "cases"]);
        return {
            kind: "PatternMatch",
            attrs: VALUE_ATTRS,
            subject: decodeValue(mo["on"], [...path, "Match", "on"]),
            cases: cases.map((entry, i) => {
                if (!Array.isArray(entry) || entry.length !== 2) {
                    fail("Match case must be [pattern, body]", [...path, "Match", "cases", i]);
                }
                return [
                    decodePattern(entry[0], [...path, "Match", "cases", i, 0]),
                    decodeValue(entry[1], [...path, "Match", "cases", i, 1]),
                ] as const;
            }),
        };
    }
    if ("Update" in o) {
        const v = o["Update"];
        if (typeof v !== "object" || v === null) fail("Update expects object", [...path, "Update"]);
        const uo = v as Record<string, unknown>;
        const subjectJson = uo["subject"];
        const fields: Array<readonly [Name, Value<TypeAttrs, ValueAttrs>]> = [];
        for (const [k, fv] of Object.entries(uo)) {
            if (k === "subject") continue;
            fields.push([nameFromCased(k), decodeValue(fv, [...path, "Update", k])] as const);
        }
        return {
            kind: "UpdateRecord",
            attrs: VALUE_ATTRS,
            subject: decodeValue(subjectJson, [...path, "Update", "subject"]),
            fields,
        };
    }
    fail(`Unknown value tag(s) ${Object.keys(o).join(",")}`, path);
}

// ---------------------------------------------------------------------------
// Value definitions
// ---------------------------------------------------------------------------

export function decodeValueDefinition(
    json: unknown,
    path: (string | number)[] = [],
): ValueDefinition<TypeAttrs, ValueAttrs> {
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail(`Value definition must be an object`, path);
    }
    const o = json as Record<string, unknown>;
    const inputsRaw = o["inputs"];
    const inputTypes: ReadonlyArray<readonly [Name, ValueAttrs, Type<TypeAttrs>]> =
        Array.isArray(inputsRaw)
            ? inputsRaw.map((entry, i) => {
                if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
                    fail("Input entry must be a {Name: Type} object", [...path, "inputs", i]);
                }
                const eo = entry as Record<string, unknown>;
                const keys = Object.keys(eo);
                if (keys.length !== 1) fail("Input entry must have exactly one key", [...path, "inputs", i]);
                const name = keys[0]!;
                return [
                    nameFromCased(name),
                    VALUE_ATTRS,
                    decodeType(eo[name], [...path, "inputs", i, name]),
                ] as const;
            })
            : [];
    const outputType = "returns" in o ? decodeType(o["returns"], [...path, "returns"]) : UNIT_TYPE;
    const body = "body" in o ? decodeValue(o["body"], [...path, "body"]) : { kind: "Unit", attrs: VALUE_ATTRS } as const;
    return { inputTypes, outputType, body };
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

export interface SimplifiedModuleFile {
    /** Module path as a forward-slash separated string of TitleCase segments,
     *  e.g. `"US/LCR/Basics"` (no `.json` suffix). */
    readonly relPath: string;
    /** Parsed JSON contents of the module file. */
    readonly json: unknown;
}

export function decodeModule(
    json: unknown,
    path: (string | number)[] = [],
): Documented<ModuleDefinition<TypeAttrs, ValueAttrs>> {
    if (typeof json !== "object" || json === null || Array.isArray(json)) {
        fail("Module must be an object", path);
    }
    const o = json as Record<string, unknown>;
    const doc = typeof o["doc"] === "string" ? (o["doc"] as string) : "";
    const typesObj = (typeof o["types"] === "object" && o["types"] !== null && !Array.isArray(o["types"]))
        ? (o["types"] as Record<string, unknown>) : {};
    const valuesObj = (typeof o["values"] === "object" && o["values"] !== null && !Array.isArray(o["values"]))
        ? (o["values"] as Record<string, unknown>) : {};

    const types: ReadonlyArray<readonly [Name, AccessControlled<Documented<TypeDefinition<TypeAttrs>>>]> =
        Object.entries(typesObj).map(([name, def]) => {
            const documented = decodeTypeDefinition(def, [...path, "types", name]);
            return [
                nameFromCased(name),
                { access: "Public", value: documented },
            ] as const;
        });

    const values: ReadonlyArray<readonly [Name, AccessControlled<Documented<ValueDefinition<TypeAttrs, ValueAttrs>>>]> =
        Object.entries(valuesObj).map(([name, def]) => {
            const subPath = [...path, "values", name];
            const valueObj = (typeof def === "object" && def !== null && !Array.isArray(def))
                ? (def as Record<string, unknown>) : fail("value def must be object", subPath);
            const docStr = typeof valueObj["doc"] === "string" ? (valueObj["doc"] as string) : "";
            const valueDef = decodeValueDefinition(def, subPath);
            return [
                nameFromCased(name),
                { access: "Public", value: { doc: docStr, value: valueDef } },
            ] as const;
        });

    return { doc, value: { types, values, doc: doc.length ? doc : null } };
}

/**
 * Convert a relative module file path (e.g. `"US/LCR/Basics.json"` or
 * `"US/LCR/Basics"`) into a Morphir module path.
 */
export function modulePathFromRelPath(relPath: string): Path {
    const trimmed = relPath.replace(/\\/g, "/").replace(/\.json$/i, "");
    const segments = trimmed.split("/").filter((s) => s.length > 0);
    return segments.map(nameFromCased);
}

/**
 * Inflate a set of simplified module files into a `SubstrateDistribution`.
 *
 * @param packageName  The package path (e.g. `[["regulation"]]` for
 *                     `Regulation`).  The simplified format doesn't carry
 *                     the package name, so the caller must supply it.
 * @param files        Per-module file contents.
 */
export function buildDistribution(
    packageName: Path,
    files: ReadonlyArray<SimplifiedModuleFile>,
): SubstrateDistribution {
    const modules: Array<readonly [Path, AccessControlled<ModuleDefinition<TypeAttrs, ValueAttrs>>]> = [];
    for (const file of files) {
        const modPath = modulePathFromRelPath(file.relPath);
        const documented = decodeModule(file.json, [file.relPath]);
        modules.push([
            modPath,
            { access: "Public", value: documented.value },
        ] as const);
    }
    const packageDef: PackageDefinition<TypeAttrs, ValueAttrs> = { modules };
    return {
        kind: "Library",
        packageName,
        dependencies: [],
        packageDef,
    };
}

// ---------------------------------------------------------------------------
// Convenience: derive package name from FQNames in the modules.
// ---------------------------------------------------------------------------

/**
 * Walk the JSON looking for the first FQName string and return its
 * package path.  Lets callers infer the package name without specifying
 * it explicitly.  Returns `null` if no FQName is found.
 */
export function inferPackageName(files: ReadonlyArray<SimplifiedModuleFile>): Path | null {
    for (const file of files) {
        const found = firstFqnIn(file.json);
        if (found) return pathFromDotted(found.split(":")[0]!);
    }
    return null;
}

function firstFqnIn(json: unknown): string | null {
    if (typeof json === "string" && /^[A-Z][\w.]*:[\w.]*:[A-Za-z_][\w]*$/.test(json)) {
        return json;
    }
    if (Array.isArray(json)) {
        for (const it of json) {
            const r = firstFqnIn(it);
            if (r) return r;
        }
    } else if (typeof json === "object" && json !== null) {
        for (const v of Object.values(json as Record<string, unknown>)) {
            const r = firstFqnIn(v);
            if (r) return r;
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Result wrapper
// ---------------------------------------------------------------------------

export type SimplifiedDecodeResult<T> =
    | { readonly ok: true; readonly value: T }
    | { readonly ok: false; readonly error: SimplifiedDecodeError };

export function tryBuildDistribution(
    packageName: Path,
    files: ReadonlyArray<SimplifiedModuleFile>,
): SimplifiedDecodeResult<SubstrateDistribution> {
    try {
        return { ok: true, value: buildDistribution(packageName, files) };
    } catch (e) {
        if (e instanceof SimplifiedDecodeError) return { ok: false, error: e };
        return { ok: false, error: new SimplifiedDecodeError(String(e)) };
    }
}

/** Re-export for ergonomic consumption alongside other IR types. */
export type { Distribution, SubstrateDistribution };
