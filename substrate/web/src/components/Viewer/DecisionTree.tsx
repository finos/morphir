/**
 * Generic decision-tree visualisation, faithfully ported from the Elm
 * `Morphir.Visual.Components.DecisionTree` component.
 *
 * Layout algorithm: each branch node renders in one of two directions
 * (Vertical or Horizontal). The root starts Vertical. At every branch
 * we measure both subtrees and place one of them in the current
 * direction while the other switches to the perpendicular one. The
 * non-continuing subtree sits next to the condition with a right
 * arrow; the continuing subtree sits below with a down arrow.
 *
 * Highlighting follows `selectedBranch`: the chosen branch and all of
 * its descendants render in the highlight colour; the other branch
 * and the condition (when a branch is selected) render dimmed.
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

type Direction = "vertical" | "horizontal";

export function DecisionTree({ node }: DecisionTreeProps): JSX.Element {
    return <NodeView node={node} direction="vertical" highlighted={false} />;
}

function NodeView({
    node,
    direction,
    highlighted,
}: {
    node: DecisionTreeNode;
    direction: Direction;
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
    return <BranchLayout node={node} direction={direction} />;
}

function BranchLayout({
    node,
    direction,
}: {
    node: BranchNode;
    direction: Direction;
}): JSX.Element {
    const thenState = node.selectedBranch === "then";
    const elseState = node.selectedBranch === "else";
    const conditionState = node.selectedBranch !== undefined;
    const opposite: Direction = direction === "vertical" ? "horizontal" : "vertical";
    const thenLabel = node.thenLabel ?? "Yes";
    const elseLabel = node.elseLabel ?? "No";

    const condition = (
        <div
            className={`${styles.condition} ${conditionState ? styles.highlighted : ""}`}
        >
            {node.condition}
        </div>
    );

    if (direction === "vertical") {
        const swap = isThenBranchLonger(node);
        const branch1Label = swap ? thenLabel : elseLabel;
        const branch1State = swap ? thenState : elseState;
        const branch1Node = swap ? node.thenBranch : node.elseBranch;
        const branch1Dir: Direction = swap ? direction : opposite;
        const branch2Label = swap ? elseLabel : thenLabel;
        const branch2State = swap ? elseState : thenState;
        const branch2Node = swap ? node.elseBranch : node.thenBranch;
        const branch2Dir: Direction = swap ? opposite : direction;

        return (
            <VerticalLayout
                condition={condition}
                branch1Label={branch1Label}
                branch1State={branch1State}
                branch1={
                    <NodeView
                        node={branch1Node}
                        direction={branch1Dir}
                        highlighted={branch1State}
                    />
                }
                branch2Label={branch2Label}
                branch2State={branch2State}
                branch2={
                    <NodeView
                        node={branch2Node}
                        direction={branch2Dir}
                        highlighted={branch2State}
                    />
                }
            />
        );
    }

    return (
        <HorizontalLayout
            condition={condition}
            branch1Label={elseLabel}
            branch1State={elseState}
            branch1={
                <NodeView
                    node={node.elseBranch}
                    direction={opposite}
                    highlighted={elseState}
                />
            }
            branch2Label={thenLabel}
            branch2State={thenState}
            branch2={
                <NodeView
                    node={node.thenBranch}
                    direction={direction}
                    highlighted={thenState}
                />
            }
        />
    );
}

// Preserved verbatim from the Elm source — note that the function
// returns true when the *else* branch is at least as deep as the
// *then* branch (the Elm name is misleading). Toggling `swap` on this
// result is what causes the longer subtree to continue in the current
// layout direction.
function isThenBranchLonger(node: BranchNode): boolean {
    const thenDepth = Math.max(
        depthOf("then", node.thenBranch),
        depthOf("else", node.thenBranch),
    );
    const elseDepth = Math.max(
        depthOf("then", node.elseBranch),
        depthOf("else", node.elseBranch),
    );
    return thenDepth <= elseDepth;
}

function depthOf(path: "then" | "else", node: DecisionTreeNode): number {
    if (node.kind === "leaf") return 1;
    const next = path === "then" ? node.thenBranch : node.elseBranch;
    return depthOf(path, next) + 1;
}

interface LayoutProps {
    condition: ReactNode;
    branch1Label: string;
    branch1State: boolean;
    branch1: ReactNode;
    branch2Label: string;
    branch2State: boolean;
    branch2: ReactNode;
}

function VerticalLayout({
    condition,
    branch1Label,
    branch1State,
    branch1,
    branch2Label,
    branch2State,
    branch2,
}: LayoutProps): JSX.Element {
    return (
        <div className={styles.vLayout}>
            <div className={styles.vTopRow}>
                <div className={styles.vConditionCol}>
                    {condition}
                    <div className={styles.vDownArrowRow}>
                        <DownArrow active={branch2State} />
                        <div
                            className={`${styles.label} ${branch2State ? styles.highlighted : ""}`}
                        >
                            {branch2Label}
                        </div>
                    </div>
                </div>
                <div className={styles.vArrowCol}>
                    <RightArrow active={branch1State} />
                    <div
                        className={`${styles.label} ${styles.labelCenter} ${branch1State ? styles.highlighted : ""}`}
                    >
                        {branch1Label}
                    </div>
                </div>
                <div className={styles.vBranch1}>{branch1}</div>
            </div>
            <div className={styles.vBranch2}>{branch2}</div>
        </div>
    );
}

function HorizontalLayout({
    condition,
    branch1Label,
    branch1State,
    branch1,
    branch2Label,
    branch2State,
    branch2,
}: LayoutProps): JSX.Element {
    return (
        <div className={styles.hLayout}>
            <div className={styles.hLeftCol}>
                <div className={styles.hTopRow}>
                    <div className={styles.hConditionCol}>
                        {condition}
                        <div className={styles.hDownArrowRow}>
                            <DownArrow active={branch1State} />
                            <div
                                className={`${styles.label} ${branch1State ? styles.highlighted : ""}`}
                            >
                                {branch1Label}
                            </div>
                        </div>
                    </div>
                    <div className={styles.hArrowCol}>
                        <RightArrow active={branch2State} />
                        <div
                            className={`${styles.label} ${styles.labelCenter} ${branch2State ? styles.highlighted : ""}`}
                        >
                            {branch2Label}
                        </div>
                    </div>
                </div>
                <div className={styles.hBranch1}>{branch1}</div>
            </div>
            <div className={styles.hBranch2}>{branch2}</div>
        </div>
    );
}

function RightArrow({ active }: { active: boolean }): JSX.Element {
    const cls = active ? styles.arrowActive : styles.arrowIdle;
    return (
        <div className={`${styles.rightArrow} ${cls}`}>
            <span className={styles.rightArrowLine} aria-hidden="true" />
            <svg
                className={styles.rightArrowHead}
                viewBox="0 0 200 200"
                aria-hidden="true"
            >
                <polygon points="0,0 200,100 0,200" />
            </svg>
        </div>
    );
}

function DownArrow({ active }: { active: boolean }): JSX.Element {
    const cls = active ? styles.arrowActive : styles.arrowIdle;
    return (
        <div className={`${styles.downArrow} ${cls}`}>
            <span className={styles.downArrowLine} aria-hidden="true" />
            <svg
                className={styles.downArrowHead}
                viewBox="0 0 200 200"
                aria-hidden="true"
            >
                <polygon points="0,0 100,200 200,0" />
            </svg>
        </div>
    );
}

export const isDecisionTreeShape = (keys: readonly string[]): boolean => {
    const set = new Set(keys);
    return set.has("if") && set.has("then") && set.has("else");
};
