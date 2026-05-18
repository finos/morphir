/**
 * Generic decision-tree visualisation, modelled on the Elm
 * `Morphir.Visual.Components.DecisionTree` component. A tree is a
 * condition node with two branches; each branch is itself another tree
 * or a leaf. We render condition boxes connected by labelled arrows
 * so that the active path (when `selectedBranch` is set on a node) is
 * highlighted.
 */
import type { JSX, ReactNode } from "react";
import styles from "./DecisionTree.module.css";

export type DecisionTreeNode = BranchNode | LeafNode;

export interface BranchNode {
    readonly kind: "branch";
    readonly condition: ReactNode;
    /** undefined means we don't know which branch is taken at runtime. */
    readonly selectedBranch?: "then" | "else";
    readonly thenLabel?: string;
    readonly elseLabel?: string;
    readonly thenBranch: DecisionTreeNode;
    readonly elseBranch: DecisionTreeNode;
}

export interface LeafNode {
    readonly kind: "leaf";
    readonly value: ReactNode;
}

export interface DecisionTreeProps {
    readonly node: DecisionTreeNode;
}

export function DecisionTree({ node }: DecisionTreeProps): JSX.Element {
    return <NodeView node={node} highlighted={false} />;
}

function NodeView({
    node,
    highlighted,
}: {
    node: DecisionTreeNode;
    highlighted: boolean;
}): JSX.Element {
    if (node.kind === "leaf") {
        return (
            <div
                className={`${styles.leaf} ${highlighted ? styles.highlighted : ""}`}
            >
                {node.value}
            </div>
        );
    }
    return <BranchView node={node} />;
}

function BranchView({ node }: { node: BranchNode }): JSX.Element {
    const thenActive = node.selectedBranch === "then";
    const elseActive = node.selectedBranch === "else";
    const conditionActive = node.selectedBranch !== undefined;
    return (
        <div className={styles.branch}>
            <div
                className={`${styles.condition} ${
                    conditionActive ? styles.highlighted : ""
                }`}
            >
                {node.condition}
            </div>
            <div className={styles.branches}>
                <BranchArm
                    label={node.thenLabel ?? "true"}
                    active={thenActive}
                    flavour="then"
                >
                    <NodeView node={node.thenBranch} highlighted={thenActive} />
                </BranchArm>
                <BranchArm
                    label={node.elseLabel ?? "false"}
                    active={elseActive}
                    flavour="else"
                >
                    <NodeView node={node.elseBranch} highlighted={elseActive} />
                </BranchArm>
            </div>
        </div>
    );
}

function BranchArm({
    label,
    active,
    flavour,
    children,
}: {
    label: string;
    active: boolean;
    flavour: "then" | "else";
    children: ReactNode;
}): JSX.Element {
    return (
        <div
            className={`${styles.arm} ${styles[flavour] ?? ""} ${
                active ? styles.highlighted : ""
            }`}
        >
            <div className={styles.armLabel}>
                <span className={styles.armLine} aria-hidden="true" />
                <span className={styles.armText}>{label}</span>
            </div>
            <div className={styles.armBody}>{children}</div>
        </div>
    );
}

export const isDecisionTreeShape = (keys: readonly string[]): boolean => {
    const set = new Set(keys);
    return set.has("if") && set.has("then") && set.has("else");
};
