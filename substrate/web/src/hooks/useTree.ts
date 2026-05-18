import { useCallback, useEffect, useState } from "react";
import { fetchTree } from "../api/client";
import type { TreeNode } from "../types";

export interface UseTreeResult {
    readonly tree: TreeNode | null;
    readonly error: Error | null;
    /** Trigger an out-of-band refresh (e.g. after a watcher event). */
    readonly refresh: () => void;
}

export function useTree(): UseTreeResult {
    const [tree, setTree] = useState<TreeNode | null>(null);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(() => {
        fetchTree()
            .then((t) => {
                setTree(t);
                setError(null);
            })
            .catch((err: unknown) => {
                setError(err instanceof Error ? err : new Error(String(err)));
            });
    }, []);

    useEffect(() => {
        refresh();
    }, [refresh]);

    return { tree, error, refresh };
}
