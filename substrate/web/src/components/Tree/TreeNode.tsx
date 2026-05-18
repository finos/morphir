import type { TreeNode } from "../../types";
import styles from "./Tree.module.css";

export interface TreeNodeProps {
    readonly node: TreeNode;
    readonly activePath: string | null;
    readonly expanded: ReadonlySet<string>;
    readonly onSelect: (path: string) => void;
    readonly onToggle: (path: string) => void;
}

export function TreeNodeRow({
    node,
    activePath,
    expanded,
    onSelect,
    onToggle,
}: TreeNodeProps): JSX.Element {
    if (node.type === "file") {
        const isActive = activePath === node.path;
        const label = node.name.replace(/\.md$/i, "");
        return (
            <li>
                <button
                    type="button"
                    className={`${styles.row} ${isActive ? styles.active : ""}`}
                    onClick={() => onSelect(node.path)}
                    title={node.path}
                    aria-current={isActive ? "true" : undefined}
                >
                    <span className={styles.caret} />
                    <span className={styles.icon} aria-hidden="true">
                        ·
                    </span>
                    <span>{label}</span>
                </button>
            </li>
        );
    }

    const isOpen = expanded.has(node.path);
    return (
        <li>
            <button
                type="button"
                className={styles.row}
                onClick={() => onToggle(node.path)}
                title={node.path || "/"}
                aria-expanded={isOpen}
            >
                <span className={styles.caret}>{isOpen ? "▾" : "▸"}</span>
                <span className={styles.icon} aria-hidden="true">
                    ▦
                </span>
                <span>{node.name}</span>
            </button>
            {isOpen && node.children && node.children.length > 0 && (
                <ul className={styles.children}>
                    {node.children.map((child) => (
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
        </li>
    );
}
