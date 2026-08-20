import { useCallback, useEffect, useState } from "react";
import type { TreeNode } from "../../types";
import { TreeNodeRow } from "./TreeNode";
import styles from "./Tree.module.css";

export interface TreeProps {
    readonly tree: TreeNode | null;
    readonly activePath: string | null;
    readonly onSelect: (path: string) => void;
}

/** Collect the paths of every directory in the tree. */
function collectDirPaths(node: TreeNode, into: Set<string>): void {
    if (node.type !== "dir") return;
    into.add(node.path);
    for (const child of node.children ?? []) collectDirPaths(child, into);
}

export function Tree({ tree, activePath, onSelect }: TreeProps): JSX.Element {
    // Directory open/closed state. Default: everything expanded; new
    // directories appearing in later tree refreshes also open by default.
    const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => {
        const set = new Set<string>();
        if (tree) collectDirPaths(tree, set);
        return set;
    });

    useEffect(() => {
        if (!tree) return;
        setExpanded((prev) => {
            const next = new Set(prev);
            const before = next.size;
            collectDirPaths(tree, next);
            return next.size === before ? prev : next;
        });
    }, [tree]);

    const onToggle = useCallback((path: string) => {
        setExpanded((prev) => {
            const next = new Set(prev);
            if (next.has(path)) next.delete(path);
            else next.add(path);
            return next;
        });
    }, []);

    if (!tree) {
        return (
            <nav className={styles.tree} aria-label="Files">
                <div className={styles.eyebrow}>Loading…</div>
            </nav>
        );
    }

    const children = tree.children ?? [];

    return (
        <nav className={styles.tree} aria-label="Files">
            <div className={styles.eyebrow}>Files</div>
            {children.length === 0 ? (
                <div className={styles.eyebrow}>No markdown files</div>
            ) : (
                <ul className={styles.list}>
                    {children.map((child) => (
                        <TreeNodeRow
                            key={child.path}
                            node={child}
                            activePath={activePath}
                            expanded={expanded}
                            onSelect={onSelect}
                            onToggle={onToggle}
                        />
                    ))}
                </ul>
            )}
        </nav>
    );
}
