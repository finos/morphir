/**
 * Source-location index for a `SubstrateDistribution`.
 *
 * Walks the distribution and collects the optional `src` attribute from every
 * type node (`TypeAttrs`) and every value/pattern node (`ValueAttrs`), then
 * builds two complementary indices:
 *
 * - **forward**: IR node path (dot-separated string) → `SourceLocation`
 * - **reverse**: location key (`"<file>#<sectionId>"`) → set of IR node paths
 *
 * The IR node path is a dot-separated string of the form:
 * `<packageName>.<modulePath>.<typeOrValueName>.<nested...>`
 *
 * This module is intentionally free of I/O; all functions are pure.
 */

import type { SourceLocation } from "../substrate/ast.js";
import type {
    ModuleDefinition,
    Pattern,
    Type,
    TypeDefinition,
    Value,
    ValueDefinition,
} from "./distribution.js";
import type { SubstrateDistribution, TypeAttrs, ValueAttrs } from "./attrs.js";

// ---------------------------------------------------------------------------
// Index types
// ---------------------------------------------------------------------------

/** A dot-separated path to an IR node, e.g. `"sample.moduleA.myType"`. */
export type NodePath = string;

/**
 * A stable key derived from a `SourceLocation`:
 * `"<file>#<sectionId>"`.
 */
export type LocationKey = string;

export interface SourceLocationIndex {
    /** Forward index: IR node path → source location. */
    readonly forward: ReadonlyMap<NodePath, SourceLocation>;
    /** Reverse index: location key → set of IR node paths. */
    readonly reverse: ReadonlyMap<LocationKey, ReadonlySet<NodePath>>;
}

// ---------------------------------------------------------------------------
// Key helpers
// ---------------------------------------------------------------------------

function locationKey(src: SourceLocation): LocationKey {
    return `${src.file}#${src.sectionId}`;
}

// ---------------------------------------------------------------------------
// Index builder
// ---------------------------------------------------------------------------

class IndexBuilder {
    readonly forward = new Map<NodePath, SourceLocation>();
    readonly reverse = new Map<LocationKey, Set<NodePath>>();

    add(path: NodePath, src: SourceLocation): void {
        this.forward.set(path, src);
        const key = locationKey(src);
        let set = this.reverse.get(key);
        if (!set) {
            set = new Set();
            this.reverse.set(key, set);
        }
        set.add(path);
    }

    record(path: NodePath, src: SourceLocation | undefined): void {
        if (src) this.add(path, src);
    }
}

// ---------------------------------------------------------------------------
// Walkers
// ---------------------------------------------------------------------------

function walkTypeAttrs(builder: IndexBuilder, path: NodePath, attrs: TypeAttrs): void {
    builder.record(path, attrs.src);
}

function walkValueAttrs(builder: IndexBuilder, path: NodePath, attrs: ValueAttrs): void {
    builder.record(path, attrs.src);
    walkType(builder, `${path}.$type`, attrs.type);
}

function walkType(builder: IndexBuilder, path: NodePath, t: Type<TypeAttrs>): void {
    walkTypeAttrs(builder, path, t.attrs);
    switch (t.kind) {
        case "Variable":
        case "Unit":
            break;
        case "Reference":
            t.typeParams.forEach((p, i) => walkType(builder, `${path}.param[${i}]`, p));
            break;
        case "Tuple":
            t.elements.forEach((el, i) => walkType(builder, `${path}.elem[${i}]`, el));
            break;
        case "Record":
        case "ExtensibleRecord":
            t.fields.forEach((f) => walkType(builder, `${path}.${f.name.join("_")}`, f.tpe));
            break;
        case "Function":
            walkType(builder, `${path}.arg`, t.argumentType);
            walkType(builder, `${path}.ret`, t.returnType);
            break;
    }
}

function walkTypeDef(builder: IndexBuilder, path: NodePath, def: TypeDefinition<TypeAttrs>): void {
    switch (def.kind) {
        case "TypeAliasDefinition":
            walkType(builder, `${path}.expr`, def.expr);
            break;
        case "CustomTypeDefinition":
            def.constructors.value.forEach(([ctorName, args]) => {
                const ctorPath = `${path}.${ctorName.join("_")}`;
                args.forEach(([argName, argType]) =>
                    walkType(builder, `${ctorPath}.${argName.join("_")}`, argType),
                );
            });
            break;
    }
}

function walkPattern(builder: IndexBuilder, path: NodePath, p: Pattern<ValueAttrs>): void {
    walkValueAttrs(builder, path, p.attrs);
    switch (p.kind) {
        case "WildcardPattern":
        case "EmptyListPattern":
        case "LiteralPattern":
        case "UnitPattern":
            break;
        case "AsPattern":
            walkPattern(builder, `${path}.pattern`, p.pattern);
            break;
        case "TuplePattern":
            p.elements.forEach((el, i) => walkPattern(builder, `${path}[${i}]`, el));
            break;
        case "ConstructorPattern":
            p.args.forEach((arg, i) => walkPattern(builder, `${path}[${i}]`, arg));
            break;
        case "HeadTailPattern":
            walkPattern(builder, `${path}.head`, p.head);
            walkPattern(builder, `${path}.tail`, p.tail);
            break;
    }
}

function walkValue(builder: IndexBuilder, path: NodePath, v: Value<TypeAttrs, ValueAttrs>): void {
    walkValueAttrs(builder, path, v.attrs);
    switch (v.kind) {
        case "Literal":
        case "Constructor":
        case "Variable":
        case "Reference":
        case "FieldFunction":
        case "Unit":
            break;
        case "Tuple":
            v.elements.forEach((el, i) => walkValue(builder, `${path}[${i}]`, el));
            break;
        case "List":
            v.items.forEach((item, i) => walkValue(builder, `${path}[${i}]`, item));
            break;
        case "Record":
            v.fields.forEach(([name, val]) =>
                walkValue(builder, `${path}.${name.join("_")}`, val),
            );
            break;
        case "Field":
            walkValue(builder, `${path}.subject`, v.subject);
            break;
        case "Apply":
            walkValue(builder, `${path}.fn`, v.function);
            walkValue(builder, `${path}.arg`, v.argument);
            break;
        case "Lambda":
            walkPattern(builder, `${path}.pattern`, v.argumentPattern);
            walkValue(builder, `${path}.body`, v.body);
            break;
        case "LetDefinition":
            walkValueDef(builder, `${path}.def`, v.definition);
            walkValue(builder, `${path}.in`, v.inValue);
            break;
        case "LetRecursion":
            v.definitions.forEach(([name, def]) =>
                walkValueDef(builder, `${path}.${name.join("_")}`, def),
            );
            walkValue(builder, `${path}.in`, v.inValue);
            break;
        case "Destructure":
            walkPattern(builder, `${path}.pattern`, v.pattern);
            walkValue(builder, `${path}.value`, v.valueToDestruct);
            walkValue(builder, `${path}.in`, v.inValue);
            break;
        case "IfThenElse":
            walkValue(builder, `${path}.cond`, v.condition);
            walkValue(builder, `${path}.then`, v.thenBranch);
            walkValue(builder, `${path}.else`, v.elseBranch);
            break;
        case "PatternMatch":
            walkValue(builder, `${path}.subject`, v.subject);
            v.cases.forEach(([pat, body], i) => {
                walkPattern(builder, `${path}.case[${i}].pat`, pat);
                walkValue(builder, `${path}.case[${i}].body`, body);
            });
            break;
        case "UpdateRecord":
            walkValue(builder, `${path}.subject`, v.subject);
            v.fields.forEach(([name, val]) =>
                walkValue(builder, `${path}.${name.join("_")}`, val),
            );
            break;
    }
}

function walkValueDef(
    builder: IndexBuilder,
    path: NodePath,
    def: ValueDefinition<TypeAttrs, ValueAttrs>,
): void {
    walkValue(builder, `${path}.body`, def.body);
}

function walkModuleDef(
    builder: IndexBuilder,
    path: NodePath,
    def: ModuleDefinition<TypeAttrs, ValueAttrs>,
): void {
    for (const [typeName, acDocTypeDef] of def.types) {
        const typePath = `${path}.${typeName.join("_")}`;
        walkTypeDef(builder, typePath, acDocTypeDef.value.value);
    }
    for (const [valueName, acDocValueDef] of def.values) {
        const valuePath = `${path}.${valueName.join("_")}`;
        walkValueDef(builder, valuePath, acDocValueDef.value.value);
    }
}

function pathSegment(path: import("./distribution.js").Path): string {
    return path.map((name) => name.join("_")).join(".");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Build forward and reverse source-location indices for a distribution.
 */
export function buildSourceLocationIndex(dist: SubstrateDistribution): SourceLocationIndex {
    const builder = new IndexBuilder();
    const pkgSegment = pathSegment(dist.packageName);

    for (const [modulePath, acModuleDef] of dist.packageDef.modules) {
        const moduleSegment = pathSegment(modulePath);
        const moduleFull = `${pkgSegment}.${moduleSegment}`;
        walkModuleDef(builder, moduleFull, acModuleDef.value);
    }

    return { forward: builder.forward, reverse: builder.reverse };
}

/**
 * Look up the source location for an IR node by its dot-separated path.
 */
export function lookupByNodePath(
    index: SourceLocationIndex,
    nodePath: NodePath,
): SourceLocation | undefined {
    return index.forward.get(nodePath);
}

/**
 * Look up all IR node paths anchored to a given file + sectionId.
 */
export function lookupByLocation(
    index: SourceLocationIndex,
    file: string,
    sectionId: string,
): ReadonlySet<NodePath> {
    return index.reverse.get(`${file}#${sectionId}`) ?? new Set();
}
