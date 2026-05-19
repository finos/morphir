/**
 * React renderer for a parsed substrate YAML block. Walks the AST,
 * swapping in `<TypeDiagram>`, `<DecisionTree>` and `<DecisionTable>`
 * for the relevant shapes. Each src-bearing node carries a
 * `data-src-id` attribute that links it to a phrase in the prose; the
 * src text itself is never shown in the visualisation.
 */
import { useMemo, type JSX, type ReactNode } from "react";

import type { YamlNode } from "./yaml";
import { DecisionTree, type DecisionTreeNode } from "./DecisionTree";
import { DecisionTable, type DecisionTableRow } from "./DecisionTable";
import { TypeDiagram, type TypeVariant } from "./TypeDiagram";
import styles from "./SubstrateBlock.module.css";

export interface SrcRef {
    /** Stable per-block id, used to link viz and prose. */
    readonly id: string;
    readonly text: string;
}

interface CollectCtx {
    readonly blockId: string;
    refs: SrcRef[];
}

const collectSrcId = (
    ctx: CollectCtx,
    text: string | null,
): string | undefined => {
    if (!text) return undefined;
    const id = `${ctx.blockId}:${ctx.refs.length}`;
    ctx.refs.push({ id, text });
    return id;
};

export interface SubstrateBlockProps {
    readonly blockId: string;
    readonly ast: YamlNode;
    readonly onRefs?: (refs: readonly SrcRef[]) => void;
}

export function SubstrateBlock({
    blockId,
    ast,
    onRefs,
}: SubstrateBlockProps): JSX.Element {
    const { content, refs } = useMemo(() => {
        const ctx: CollectCtx = { blockId, refs: [] };
        const body =
            ast.kind === "mapping"
                ? (ast.entries.find(([k]) => k === "substrate")?.[1] ?? ast)
                : ast;
        const element = renderNode(body, ctx, null);
        return { content: element, refs: ctx.refs };
    }, [ast, blockId]);

    useMemo(
        () => onRefs?.(refs),
        // eslint-disable-next-line react-hooks/exhaustive-deps
        [refs.map((r) => `${r.id}|${r.text}`).join("\n")],
    );

    return <div className={styles.block}>{content}</div>;
}

const findSrc = (node: YamlNode): string | null => {
    if (node.kind !== "mapping") return null;
    for (const [k, v] of node.entries) {
        if (k === "src" && v.kind === "scalar" && typeof v.value === "string") {
            return v.value;
        }
    }
    return null;
};

const mappingKeys = (node: YamlNode): string[] =>
    node.kind === "mapping" ? node.entries.map(([k]) => k) : [];

const mappingValue = (node: YamlNode, key: string): YamlNode | null => {
    if (node.kind !== "mapping") return null;
    const entry = node.entries.find(([k]) => k === key);
    return entry ? entry[1] : null;
};

const isIfShape = (node: YamlNode): boolean => {
    if (node.kind !== "mapping") return false;
    const keys = new Set(mappingKeys(node));
    return keys.has("if") && (keys.has("then") || keys.has("else"));
};

const isMatchShape = (node: YamlNode): boolean => {
    if (node.kind !== "mapping") return false;
    const match = mappingValue(node, "match");
    if (!match || match.kind !== "mapping") return false;
    return mappingValue(match, "cases") !== null;
};

const isOneOfShape = (node: YamlNode): boolean => {
    if (node.kind !== "mapping") return false;
    const oneOf = mappingValue(node, "one-of");
    return oneOf !== null && oneOf.kind === "sequence";
};

function renderNode(
    node: YamlNode,
    ctx: CollectCtx,
    keyLabel: string | null,
): JSX.Element {
    if (node.kind === "scalar") {
        return wrapWithKey(keyLabel, renderScalar(node.value));
    }
    if (node.kind === "sequence") {
        const list = (
            <ul className={styles.sequence}>
                {node.items.map((item, i) => (
                    <li key={i} className={styles.sequenceItem}>
                        {renderNode(item, ctx, null)}
                    </li>
                ))}
            </ul>
        );
        return wrapWithKey(keyLabel, list);
    }

    if (isIfShape(node)) {
        return wrapWithKey(keyLabel, renderIf(node, ctx));
    }
    if (isMatchShape(node)) {
        return wrapWithKey(keyLabel, renderMatch(node, ctx));
    }
    if (keyLabel && isOneOfShape(node)) {
        return renderTypeDef(keyLabel, node, ctx);
    }
    return renderMapping(node, ctx, keyLabel);
}

function renderScalar(value: string | number | boolean | null): JSX.Element {
    let cls = styles.scalar ?? "";
    if (typeof value === "number") cls += " " + (styles.scalarNumber ?? "");
    else if (typeof value === "boolean")
        cls += " " + (styles.scalarBool ?? "");
    else if (value === null) cls += " " + (styles.scalarNull ?? "");
    return <span className={cls}>{value === null ? "∅" : String(value)}</span>;
}

function renderMapping(
    node: { kind: "mapping"; entries: readonly (readonly [string, YamlNode])[] },
    ctx: CollectCtx,
    keyLabel: string | null,
): JSX.Element {
    const srcId = collectSrcId(ctx, findSrc(node));
    const card = (
        <div
            className={styles.mapping}
            {...(srcId ? { "data-src-id": srcId } : {})}
        >
            {node.entries.map(([k, v], i) => {
                if (k === "src") return null;
                return (
                    <div key={`${k}-${i}`} className={styles.row}>
                        {renderNode(v, ctx, k)}
                    </div>
                );
            })}
        </div>
    );
    return wrapWithKey(keyLabel, card);
}

function renderIf(node: YamlNode, ctx: CollectCtx): JSX.Element {
    const cond = mappingValue(node, "if");
    const thenN = mappingValue(node, "then");
    const elseN = mappingValue(node, "else");
    const tree: DecisionTreeNode = {
        kind: "branch",
        condition: cond ? renderNode(cond, ctx, null) : <em>?</em>,
        thenBranch: nodeToTree(thenN, ctx),
        elseBranch: nodeToTree(elseN, ctx),
    };
    return <DecisionTree node={tree} />;
}

function nodeToTree(
    node: YamlNode | null,
    ctx: CollectCtx,
): DecisionTreeNode {
    if (!node) return { kind: "leaf", value: <em>∅</em> };
    if (isIfShape(node)) {
        const cond = mappingValue(node, "if");
        const thenN = mappingValue(node, "then");
        const elseN = mappingValue(node, "else");
        return {
            kind: "branch",
            condition: cond ? renderNode(cond, ctx, null) : <em>?</em>,
            thenBranch: nodeToTree(thenN, ctx),
            elseBranch: nodeToTree(elseN, ctx),
        };
    }
    return { kind: "leaf", value: renderNode(node, ctx, null) };
}

function renderMatch(node: YamlNode, ctx: CollectCtx): JSX.Element {
    const match = mappingValue(node, "match");
    if (!match) return <></>;
    const on = mappingValue(match, "on");
    const cases = mappingValue(match, "cases");
    const headers: ReactNode[] = [on ? renderNode(on, ctx, null) : "input"];
    const rows: DecisionTableRow[] = [];
    if (cases?.kind === "sequence") {
        for (const c of cases.items) {
            const when = mappingValue(c, "when");
            const then = mappingValue(c, "then");
            const srcId = collectSrcId(ctx, findSrc(c));
            rows.push({
                patterns: [when ? renderNode(when, ctx, null) : <em>?</em>],
                result: then ? renderNode(then, ctx, null) : <em>∅</em>,
                ...(srcId ? { srcId } : {}),
            });
        }
    }
    return <DecisionTable headers={headers} rows={rows} />;
}

function renderTypeDef(
    name: string,
    node: YamlNode,
    ctx: CollectCtx,
): JSX.Element {
    const parentSrcId = collectSrcId(ctx, findSrc(node));
    const oneOf = mappingValue(node, "one-of");
    const variants: TypeVariant[] = [];
    if (oneOf?.kind === "sequence") {
        for (const item of oneOf.items) {
            const variantName = readVariantName(item);
            const srcId = collectSrcId(ctx, findSrc(item));
            const detail = renderVariantDetail(item, ctx);
            variants.push({
                name: variantName,
                ...(srcId !== undefined ? { srcId } : {}),
                ...(detail !== null ? { detail } : {}),
            });
        }
    }
    return (
        <TypeDiagram
            parentName={name}
            {...(parentSrcId !== undefined ? { parentSrcId } : {})}
            variants={variants}
        />
    );
}

const readVariantName = (node: YamlNode): string => {
    if (node.kind === "scalar") return String(node.value ?? "");
    if (node.kind === "mapping") {
        const tag = mappingValue(node, "tag");
        if (tag?.kind === "scalar") return String(tag.value ?? "?");
        for (const [k] of node.entries) {
            if (k !== "src") return k;
        }
    }
    return "?";
};

const renderVariantDetail = (
    node: YamlNode,
    ctx: CollectCtx,
): ReactNode | null => {
    if (node.kind !== "mapping") return null;
    const extras = node.entries.filter(([k]) => k !== "tag" && k !== "src");
    if (extras.length === 0) return null;
    return (
        <div className={styles.mapping}>
            {extras.map(([k, v], i) => (
                <div key={`${k}-${i}`} className={styles.row}>
                    {renderNode(v, ctx, k)}
                </div>
            ))}
        </div>
    );
};

function wrapWithKey(
    keyLabel: string | null,
    inner: ReactNode,
): JSX.Element {
    if (!keyLabel) return <>{inner}</>;
    return (
        <div className={styles.keyed}>
            <div className={styles.key}>{keyLabel}</div>
            <div className={styles.value}>{inner}</div>
        </div>
    );
}
