/**
 * IR explorer view.  Renders a `SubstrateDistribution` inside the pan/zoom
 * `InterpretationViewport`, mounting every module in a flex column on the
 * canvas.  Each nested IR concept gets its own fixed-size `NodeSlot`, so
 * the layout stays stable no matter how deep the expression tree goes —
 * users navigate with the viewport's pan/zoom + click-to-zoom.
 */
import { type JSX } from "react";
import { InterpretationViewport } from "./InterpretationViewport";
import { NodeSlot } from "./NodeSlot";
import styles from "./IRView.module.css";

import type {
    Distribution,
    FQName,
    ModuleDefinition,
    Name,
    Pattern,
    Path,
    Type,
    TypeDefinition,
    Value,
    ValueDefinition,
} from "../../../ir";
import type { TypeAttrs, ValueAttrs } from "../../../ir";

type Dist = Distribution<TypeAttrs, ValueAttrs>;
type Mod = ModuleDefinition<TypeAttrs, ValueAttrs>;
type Tp = Type<TypeAttrs>;
type TpDef = TypeDefinition<TypeAttrs>;
type Vl = Value<TypeAttrs, ValueAttrs>;
type VlDef = ValueDefinition<TypeAttrs, ValueAttrs>;
type Pat = Pattern<ValueAttrs>;

export interface IRViewProps {
    readonly distribution: Dist;
}

export function IRView({ distribution }: IRViewProps): JSX.Element {
    const moduleCount = distribution.packageDef.modules.length;
    const typeCount = distribution.packageDef.modules.reduce(
        (n, [, m]) => n + m.value.types.length,
        0,
    );
    const valueCount = distribution.packageDef.modules.reduce(
        (n, [, m]) => n + m.value.values.length,
        0,
    );
    return (
        <div style={{ display: "flex", flexDirection: "column", flex: "1 1 0", minHeight: 0 }}>
            <div className={styles.toolbar}>
                <span className={styles.toolbarTitle}>
                    {renderPath(distribution.packageName) || "<package>"}
                </span>
                <span className={styles.toolbarMeta}>
                    {moduleCount} modules · {typeCount} types · {valueCount} values
                </span>
            </div>
            <InterpretationViewport>
                <div className={styles.modulesList}>
                    {distribution.packageDef.modules.map(([path, ac]) => (
                        <NodeSlot
                            key={renderPath(path)}
                            kind="ir-module"
                            label={renderPath(path)}
                        >
                            <ModuleView path={path} module={ac.value} />
                        </NodeSlot>
                    ))}
                </div>
            </InterpretationViewport>
        </div>
    );
}

// ---------------------------------------------------------------------------
// Module
// ---------------------------------------------------------------------------

function ModuleView({ path, module }: { path: Path; module: Mod }): JSX.Element {
    return (
        <div className={styles.module}>
            <div className={styles.moduleHeader}>
                <span className={styles.moduleKind}>module</span>
                <span className={styles.modulePath}>{renderPath(path)}</span>
            </div>
            {module.doc && <div className={styles.docNote}>{module.doc}</div>}
            {module.types.length > 0 && (
                <div className={styles.section}>
                    <div className={styles.sectionTitle}>Types</div>
                    <div className={styles.sectionGrid}>
                        {module.types.map(([name, ac]) => (
                            <NodeSlot key={renderName(name)} kind="ir-type" label={renderName(name)}>
                                <TypeCard name={name} documented={ac.value} />
                            </NodeSlot>
                        ))}
                    </div>
                </div>
            )}
            {module.values.length > 0 && (
                <div className={styles.section}>
                    <div className={styles.sectionTitle}>Values</div>
                    <div className={styles.sectionGrid}>
                        {module.values.map(([name, ac]) => (
                            <NodeSlot key={renderName(name)} kind="ir-value" label={renderName(name)}>
                                <ValueCard name={name} documented={ac.value} />
                            </NodeSlot>
                        ))}
                    </div>
                </div>
            )}
            {module.types.length === 0 && module.values.length === 0 && (
                <div className={styles.empty}>(empty module)</div>
            )}
        </div>
    );
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Documented<T> { readonly doc: string; readonly value: T; }

function TypeCard({ name, documented }: { name: Name; documented: Documented<TpDef> }): JSX.Element {
    const def = documented.value;
    return (
        <div className={styles.typeCard}>
            <div className={styles.cardHead}>
                <span className={styles.cardKind}>{def.kind === "TypeAliasDefinition" ? "alias" : "union"}</span>
                <span className={styles.cardName}>{renderName(name)}</span>
                {def.params.length > 0 && (
                    <span className={styles.cardParams}>
                        {def.params.map(renderName).join(" ")}
                    </span>
                )}
            </div>
            {documented.doc && <div className={styles.docNote}>{documented.doc.trim()}</div>}
            {def.kind === "TypeAliasDefinition"
                ? <TypeView t={def.expr} />
                : <ConstructorsView ctors={def.constructors.value} />}
        </div>
    );
}

function ConstructorsView({ ctors }: { ctors: ReadonlyArray<readonly [Name, ReadonlyArray<readonly [Name, Tp]>]> }): JSX.Element {
    if (ctors.length === 0) return <span className={styles.empty}>(no constructors)</span>;
    return (
        <div className={styles.constructors}>
            {ctors.map(([cname, args]) => (
                <div key={renderName(cname)} className={styles.ctorRow}>
                    <span className={styles.exprTok}>{titleCase(renderName(cname))}</span>
                    {args.map(([aname, atype], i) => (
                        <span key={i}>
                            <span className={styles.fieldName}>{renderName(aname)}:</span>{" "}
                            <TypeView t={atype} inline />
                        </span>
                    ))}
                </div>
            ))}
        </div>
    );
}

function TypeView({ t, inline }: { t: Tp; inline?: boolean }): JSX.Element {
    const body = renderType(t);
    return inline ? <span>{body}</span> : <div className={styles.exprRow}>{body}</div>;
}

function renderType(t: Tp): JSX.Element {
    switch (t.kind) {
        case "Variable":
            return <span className={styles.exprTok}>{renderName(t.name)}</span>;
        case "Reference": {
            const tail = t.typeParams.length === 0
                ? null
                : <> {t.typeParams.map((p, i) => <span key={i}> {renderType(p)}</span>)}</>;
            return <><span className={styles.ref}>{renderFqn(t.name)}</span>{tail}</>;
        }
        case "Tuple":
            return <>({t.elements.map((e, i) => (
                <span key={i}>{i > 0 && ", "}{renderType(e)}</span>
            ))})</>;
        case "Record":
            return <>{"{"} {t.fields.map((f, i) => (
                <span key={i}>{i > 0 && ", "}{renderName(f.name)}: {renderType(f.tpe)}</span>
            ))} {"}"}</>;
        case "ExtensibleRecord":
            return <>{"{"} {renderName(t.name)} | {t.fields.map((f, i) => (
                <span key={i}>{i > 0 && ", "}{renderName(f.name)}: {renderType(f.tpe)}</span>
            ))} {"}"}</>;
        case "Function":
            return <>{renderType(t.argumentType)} → {renderType(t.returnType)}</>;
        case "Unit":
            return <span className={styles.exprTok}>()</span>;
    }
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

function ValueCard({ name, documented }: { name: Name; documented: Documented<VlDef> }): JSX.Element {
    const def = documented.value;
    return (
        <div className={styles.valueCard}>
            <div className={styles.cardHead}>
                <span className={styles.cardKind}>value</span>
                <span className={styles.cardName}>{renderName(name)}</span>
                {def.inputTypes.length > 0 && (
                    <span className={styles.cardParams}>
                        ({def.inputTypes.map(([n]) => renderName(n)).join(", ")})
                    </span>
                )}
                <span className={styles.cardParams}>: <TypeView t={def.outputType} inline /></span>
            </div>
            {documented.doc && <div className={styles.docNote}>{documented.doc.trim()}</div>}
            {def.inputTypes.length > 0 && (
                <div className={styles.fieldRow}>
                    <span className={styles.fieldName}>inputs</span>
                    <div>
                        {def.inputTypes.map(([n, , t], i) => (
                            <div key={i}>
                                <span className={styles.exprTok}>{renderName(n)}</span>
                                <span className={styles.exprLabel}> : </span>
                                <TypeView t={t} inline />
                            </div>
                        ))}
                    </div>
                </div>
            )}
            <NodeSlot kind="ir-expr" label="body">
                <ExprView v={def.body} />
            </NodeSlot>
        </div>
    );
}

function ExprView({ v }: { v: Vl }): JSX.Element {
    return (
        <div className={styles.expr}>
            <div className={styles.exprHead}>{exprTag(v)}</div>
            <ExprBody v={v} />
        </div>
    );
}

function exprTag(v: Vl): string {
    switch (v.kind) {
        case "Literal": return v.literal.kind.replace("Literal", "").toLowerCase() || "literal";
        case "Variable": return "variable";
        case "Reference": return "reference";
        case "Constructor": return "ctor";
        case "Tuple": return "tuple";
        case "List": return "list";
        case "Record": return "record";
        case "Field": return "field";
        case "FieldFunction": return "field-fn";
        case "Apply": return "apply";
        case "Lambda": return "lambda";
        case "LetDefinition": return "let";
        case "LetRecursion": return "let-rec";
        case "Destructure": return "destructure";
        case "IfThenElse": return "if";
        case "PatternMatch": return "match";
        case "UpdateRecord": return "update";
        case "Unit": return "unit";
    }
}

function ExprBody({ v }: { v: Vl }): JSX.Element {
    switch (v.kind) {
        case "Literal": return <span className={styles.exprLit}>{renderLiteral(v.literal)}</span>;
        case "Variable": return <span className={styles.exprTok}>{renderName(v.name)}</span>;
        case "Reference": return <span className={styles.ref}>{renderFqn(v.name)}</span>;
        case "Constructor": return <span className={`${styles.ref} ${styles.ctorRef}`}>{renderFqn(v.name)}</span>;
        case "Unit": return <span className={styles.exprTok}>()</span>;
        case "FieldFunction": return <span className={styles.exprTok}>.{renderName(v.name)}</span>;
        case "Tuple":
            return <Children items={v.elements} />;
        case "List":
            return <Children items={v.items} />;
        case "Record":
            return (
                <div className={styles.indent}>
                    {v.fields.map(([n, val], i) => (
                        <div key={i}>
                            <span className={styles.fieldName}>{renderName(n)} =</span>{" "}
                            <NodeSlot kind="ir-expr" label={renderName(n)}>
                                <ExprView v={val} />
                            </NodeSlot>
                        </div>
                    ))}
                </div>
            );
        case "Field":
            return (
                <div className={styles.indent}>
                    <span className={styles.exprLabel}>.{renderName(v.fieldName)}</span>
                    <NodeSlot kind="ir-expr" label="on">
                        <ExprView v={v.subject} />
                    </NodeSlot>
                </div>
            );
        case "Apply":
            return (
                <div className={styles.indent}>
                    <NodeSlot kind="ir-expr" label="fn">
                        <ExprView v={v.function} />
                    </NodeSlot>
                    <NodeSlot kind="ir-expr" label="arg">
                        <ExprView v={v.argument} />
                    </NodeSlot>
                </div>
            );
        case "Lambda":
            return (
                <div className={styles.indent}>
                    <div>λ <PatternView p={v.argumentPattern} /> →</div>
                    <NodeSlot kind="ir-expr" label="body">
                        <ExprView v={v.body} />
                    </NodeSlot>
                </div>
            );
        case "LetDefinition":
            return (
                <div className={styles.indent}>
                    <div><span className={styles.exprLabel}>let </span><span className={styles.exprTok}>{renderName(v.name)}</span> =</div>
                    <NodeSlot kind="ir-expr" label="def">
                        <ExprView v={v.definition.body} />
                    </NodeSlot>
                    <div><span className={styles.exprLabel}>in</span></div>
                    <NodeSlot kind="ir-expr" label="in">
                        <ExprView v={v.inValue} />
                    </NodeSlot>
                </div>
            );
        case "LetRecursion":
            return (
                <div className={styles.indent}>
                    <div><span className={styles.exprLabel}>let rec</span></div>
                    {v.definitions.map(([n, d], i) => (
                        <div key={i}>
                            <span className={styles.exprTok}>{renderName(n)}</span> =
                            <NodeSlot kind="ir-expr" label={renderName(n)}>
                                <ExprView v={d.body} />
                            </NodeSlot>
                        </div>
                    ))}
                    <div><span className={styles.exprLabel}>in</span></div>
                    <NodeSlot kind="ir-expr" label="in">
                        <ExprView v={v.inValue} />
                    </NodeSlot>
                </div>
            );
        case "Destructure":
            return (
                <div className={styles.indent}>
                    <div><span className={styles.exprLabel}>let </span><PatternView p={v.pattern} /> =</div>
                    <NodeSlot kind="ir-expr" label="value">
                        <ExprView v={v.valueToDestruct} />
                    </NodeSlot>
                    <div><span className={styles.exprLabel}>in</span></div>
                    <NodeSlot kind="ir-expr" label="in">
                        <ExprView v={v.inValue} />
                    </NodeSlot>
                </div>
            );
        case "IfThenElse":
            return (
                <div className={styles.indent}>
                    <div><span className={styles.exprLabel}>if</span></div>
                    <NodeSlot kind="ir-expr" label="cond">
                        <ExprView v={v.condition} />
                    </NodeSlot>
                    <div><span className={styles.exprLabel}>then</span></div>
                    <NodeSlot kind="ir-expr" label="then">
                        <ExprView v={v.thenBranch} />
                    </NodeSlot>
                    <div><span className={styles.exprLabel}>else</span></div>
                    <NodeSlot kind="ir-expr" label="else">
                        <ExprView v={v.elseBranch} />
                    </NodeSlot>
                </div>
            );
        case "PatternMatch":
            return (
                <div className={styles.indent}>
                    <div><span className={styles.exprLabel}>match</span></div>
                    <NodeSlot kind="ir-expr" label="on">
                        <ExprView v={v.subject} />
                    </NodeSlot>
                    {v.cases.map(([p, body], i) => (
                        <div key={i}>
                            <NodeSlot kind="ir-pattern" label="pat">
                                <PatternView p={p} />
                            </NodeSlot>
                            <span className={styles.exprLabel}> → </span>
                            <NodeSlot kind="ir-expr" label="body">
                                <ExprView v={body} />
                            </NodeSlot>
                        </div>
                    ))}
                </div>
            );
        case "UpdateRecord":
            return (
                <div className={styles.indent}>
                    <NodeSlot kind="ir-expr" label="subject">
                        <ExprView v={v.subject} />
                    </NodeSlot>
                    {v.fields.map(([n, val], i) => (
                        <div key={i}>
                            <span className={styles.fieldName}>{renderName(n)} =</span>
                            <NodeSlot kind="ir-expr" label={renderName(n)}>
                                <ExprView v={val} />
                            </NodeSlot>
                        </div>
                    ))}
                </div>
            );
    }
}

function Children({ items }: { items: readonly Vl[] }): JSX.Element {
    if (items.length === 0) return <span className={styles.empty}>(empty)</span>;
    return (
        <div className={styles.indent}>
            {items.map((it, i) => (
                <NodeSlot key={i} kind="ir-expr" label={`#${i}`}>
                    <ExprView v={it} />
                </NodeSlot>
            ))}
        </div>
    );
}

// ---------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------

function PatternView({ p }: { p: Pat }): JSX.Element {
    return <span className={styles.pattern}>{renderPattern(p)}</span>;
}

function renderPattern(p: Pat): JSX.Element {
    switch (p.kind) {
        case "WildcardPattern": return <span className={styles.exprLabel}>_</span>;
        case "EmptyListPattern": return <span className={styles.exprTok}>[]</span>;
        case "UnitPattern": return <span className={styles.exprTok}>()</span>;
        case "AsPattern": return <>{renderPattern(p.pattern)} <span className={styles.exprLabel}>as</span> <span className={styles.exprTok}>{renderName(p.name)}</span></>;
        case "TuplePattern": return <>({p.elements.map((e, i) => <span key={i}>{i > 0 && ", "}{renderPattern(e)}</span>)})</>;
        case "ConstructorPattern": return <>
            <span className={`${styles.ref} ${styles.ctorRef}`}>{renderFqn(p.name)}</span>
            {p.args.map((a, i) => <span key={i}> {renderPattern(a)}</span>)}
        </>;
        case "HeadTailPattern": return <>{renderPattern(p.head)} :: {renderPattern(p.tail)}</>;
        case "LiteralPattern": return <span className={styles.exprLit}>{renderLiteral(p.literal)}</span>;
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function renderName(n: Name): string {
    // Render a Name back to camelCase: first word lower, subsequent capitalised.
    if (n.length === 0) return "";
    const [first, ...rest] = n;
    return first! + rest.map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join("");
}

function titleCase(s: string): string {
    return s.length === 0 ? s : s.charAt(0).toUpperCase() + s.slice(1);
}

function renderPath(p: Path): string {
    return p.map((n) => titleCase(renderName(n))).join(".");
}

function renderFqn(fqn: FQName): string {
    return `${renderPath(fqn[0])}:${renderPath(fqn[1])}:${renderName(fqn[2])}`;
}

function renderLiteral(l: { kind: string; value: unknown }): string {
    switch (l.kind) {
        case "StringLiteral": return JSON.stringify(l.value);
        case "CharLiteral": return `'${String(l.value)}'`;
        case "BoolLiteral": return String(l.value);
        case "WholeNumberLiteral": return String(l.value);
        case "FloatLiteral": return String(l.value);
        case "DecimalLiteral": return String(l.value);
    }
    return String(l.value);
}
