/**
 * Renders a parsed substrate `Module` (plus any parse diagnostics) as
 * the interpretation visualisation. Each AST node's
 * `src: SourceLocation[]` becomes one or more `data-src-id` anchors
 * that link the visual element to the corresponding prose span.
 */
import { useMemo, type JSX, type ReactNode } from "react";

import type {
    Apply,
    IfExpr,
    MatchExpr,
    Module,
    OneOfType,
    ParseResult,
    SourceLocation,
    ValueDefinition,
    ValueExpression,
} from "../../substrate/ast";
import { BINARY_OPS, NARY_OPS, UNARY_OPS } from "../../substrate/ast";
import { DecisionTree, type DecisionTreeNode } from "./DecisionTree";
import { DecisionTable, type DecisionTableRow } from "./DecisionTable";
import { TypeDiagram, type TypeVariant } from "./TypeDiagram";
import { Diagnostics } from "./Diagnostics";
import styles from "./SubstrateBlock.module.css";

export interface SrcRef {
    readonly id: string;
    readonly text: string;
}

interface CollectCtx {
    readonly blockId: string;
    refs: SrcRef[];
}

function collectSrcIds(
    ctx: CollectCtx,
    src: readonly SourceLocation[],
): readonly string[] {
    const ids: string[] = [];
    for (const loc of src) {
        if (!loc.text) continue;
        const id = `${ctx.blockId}:${ctx.refs.length}`;
        ctx.refs.push({ id, text: loc.text });
        ids.push(id);
    }
    return ids;
}

function firstSrcId(
    ctx: CollectCtx,
    src: readonly SourceLocation[],
): string | undefined {
    const ids = collectSrcIds(ctx, src);
    return ids[0];
}

export interface SubstrateBlockProps {
    readonly blockId: string;
    readonly result: ParseResult;
    readonly onRefs?: (refs: readonly SrcRef[]) => void;
}

export function SubstrateBlock({
    blockId,
    result,
    onRefs,
}: SubstrateBlockProps): JSX.Element {
    const { content, refs } = useMemo(() => {
        const ctx: CollectCtx = { blockId, refs: [] };
        const element = result.module ? renderModule(result.module, ctx) : null;
        return { content: element, refs: ctx.refs };
    }, [blockId, result]);

    useMemo(
        () => onRefs?.(refs),
        // eslint-disable-next-line react-hooks/exhaustive-deps
        [refs.map((r) => `${r.id}|${r.text}`).join("\n")],
    );

    return (
        <div className={styles.block}>
            <Diagnostics diagnostics={result.diagnostics} />
            {content}
        </div>
    );
}

// --- Module --------------------------------------------------------------

function renderModule(module: Module, ctx: CollectCtx): JSX.Element {
    // Eagerly attach module-level src refs so they participate in
    // prose-linking even though the module has no visible element of
    // its own.
    collectSrcIds(ctx, module.src);
    return (
        <>
            {[...module.types.entries()].map(([name, def]) => (
                <div key={`type-${name}`} className={styles.row}>
                    {renderTypeDefinition(name, def, ctx)}
                </div>
            ))}
            {[...module.values.entries()].map(([name, def]) => (
                <div key={`value-${name}`} className={styles.row}>
                    {renderValueDefinition(name, def, ctx)}
                </div>
            ))}
        </>
    );
}

function renderTypeDefinition(
    name: string,
    def: OneOfType,
    ctx: CollectCtx,
): JSX.Element {
    const parentSrcId = firstSrcId(ctx, def.src);
    const variants: TypeVariant[] = def.variants.map((v) => {
        const srcId = firstSrcId(ctx, v.src);
        return {
            name: v.name,
            ...(srcId !== undefined ? { srcId } : {}),
        };
    });
    return (
        <TypeDiagram
            parentName={name}
            {...(parentSrcId !== undefined ? { parentSrcId } : {})}
            variants={variants}
        />
    );
}

function renderValueDefinition(
    name: string,
    def: ValueDefinition,
    ctx: CollectCtx,
): JSX.Element {
    const headerIds = collectSrcIds(ctx, def.src);
    const headerAttr =
        headerIds[0] !== undefined ? { "data-src-id": headerIds[0] } : {};
    return (
        <div className={styles.keyed}>
            <div className={styles.key} {...headerAttr}>
                {name}
                {def.params.length > 0 && (
                    <span className={styles.paramList}>
                        ({def.params.join(", ")})
                    </span>
                )}
            </div>
            <div className={styles.value}>
                {renderExpression(def.body, ctx)}
            </div>
        </div>
    );
}

// --- Expressions ---------------------------------------------------------

function renderExpression(
    expr: ValueExpression,
    ctx: CollectCtx,
): JSX.Element {
    switch (expr.kind) {
        case "literal-string":
            return renderScalar(expr.value, "string", expr.src, ctx);
        case "literal-number":
            return renderScalar(expr.value, "number", expr.src, ctx);
        case "literal-boolean":
            return renderScalar(expr.value, "boolean", expr.src, ctx);
        case "literal-null":
            return renderScalar(null, "null", expr.src, ctx);
        case "variable":
            return renderVariable(expr.name, expr.src, ctx);
        case "if":
            return renderIf(expr, ctx);
        case "match":
            return renderMatch(expr, ctx);
        default:
            // The remaining kinds all belong to Apply.
            return renderApply(expr, ctx);
    }
}

function renderScalar(
    value: string | number | boolean | null,
    type: "string" | "number" | "boolean" | "null",
    src: readonly SourceLocation[],
    ctx: CollectCtx,
): JSX.Element {
    const srcId = firstSrcId(ctx, src);
    let cls = styles.scalar ?? "";
    if (type === "number") cls += " " + (styles.scalarNumber ?? "");
    else if (type === "boolean") cls += " " + (styles.scalarBool ?? "");
    else if (type === "null") cls += " " + (styles.scalarNull ?? "");
    return (
        <span
            className={cls}
            {...(srcId ? { "data-src-id": srcId } : {})}
        >
            {value === null
                ? "∅"
                : type === "string"
                  ? `"${String(value)}"`
                  : String(value)}
        </span>
    );
}

function renderVariable(
    name: string,
    src: readonly SourceLocation[],
    ctx: CollectCtx,
): JSX.Element {
    const srcId = firstSrcId(ctx, src);
    return (
        <span
            className={styles.variable}
            {...(srcId ? { "data-src-id": srcId } : {})}
        >
            {name}
        </span>
    );
}

function renderIf(expr: IfExpr, ctx: CollectCtx): JSX.Element {
    // Promote the if's own src refs onto its condition for visibility —
    // there's no dedicated visual element for the if itself.
    collectSrcIds(ctx, expr.src);
    const tree: DecisionTreeNode = {
        kind: "branch",
        condition: renderExpression(expr.condition, ctx),
        thenBranch: exprToTree(expr.then, ctx),
        elseBranch: exprToTree(expr.else, ctx),
    };
    return <DecisionTree node={tree} />;
}

function exprToTree(
    expr: ValueExpression,
    ctx: CollectCtx,
): DecisionTreeNode {
    if (expr.kind === "if") {
        collectSrcIds(ctx, expr.src);
        return {
            kind: "branch",
            condition: renderExpression(expr.condition, ctx),
            thenBranch: exprToTree(expr.then, ctx),
            elseBranch: exprToTree(expr.else, ctx),
        };
    }
    return { kind: "leaf", value: renderExpression(expr, ctx) };
}

function renderMatch(expr: MatchExpr, ctx: CollectCtx): JSX.Element {
    collectSrcIds(ctx, expr.src);
    const headers: ReactNode[] = [renderExpression(expr.on, ctx)];
    const rows: DecisionTableRow[] = expr.cases.map((c) => {
        const srcId = firstSrcId(ctx, c.src);
        const row: DecisionTableRow = {
            patterns: [renderExpression(c.when, ctx)],
            result: renderExpression(c.then, ctx),
            ...(srcId !== undefined ? { srcId } : {}),
        };
        return row;
    });
    return <DecisionTable headers={headers} rows={rows} />;
}

// --- Apply ---------------------------------------------------------------

const OP_SYMBOL: Partial<Record<Apply["kind"], string>> = {
    equals: "=",
    "not-equals": "≠",
    "less-than": "<",
    "less-than-or-equal": "≤",
    "greater-than": ">",
    "greater-than-or-equal": "≥",
    add: "+",
    subtract: "−",
    multiply: "×",
    divide: "÷",
    and: "and",
    or: "or",
    not: "not",
    concat: "++",
    contains: "contains",
    "starts-with": "starts with",
    "ends-with": "ends with",
};

function renderApply(expr: Apply, ctx: CollectCtx): JSX.Element {
    const srcId = firstSrcId(ctx, expr.src);
    const wrap = (inner: ReactNode): JSX.Element => (
        <span
            className={styles.apply}
            {...(srcId ? { "data-src-id": srcId } : {})}
        >
            {inner}
        </span>
    );
    const sym = OP_SYMBOL[expr.kind] ?? expr.kind;

    if ((UNARY_OPS as readonly string[]).includes(expr.kind)) {
        const e = expr as Extract<Apply, { operand: ValueExpression }>;
        return wrap(
            <>
                <span className={styles.op}>{sym}</span>{" "}
                {renderExpression(e.operand, ctx)}
            </>,
        );
    }
    if ((BINARY_OPS as readonly string[]).includes(expr.kind)) {
        const e = expr as Extract<Apply, { left: ValueExpression }>;
        return wrap(
            <>
                {renderExpression(e.left, ctx)}{" "}
                <span className={styles.op}>{sym}</span>{" "}
                {renderExpression(e.right, ctx)}
            </>,
        );
    }
    if ((NARY_OPS as readonly string[]).includes(expr.kind)) {
        const e = expr as Extract<Apply, { args: readonly ValueExpression[] }>;
        return wrap(
            <>
                {e.args.map((a, i) => (
                    <span key={i}>
                        {i > 0 && (
                            <span className={styles.op}>{" " + sym + " "}</span>
                        )}
                        {renderExpression(a, ctx)}
                    </span>
                ))}
            </>,
        );
    }
    return wrap(<span className={styles.op}>{sym}</span>);
}
