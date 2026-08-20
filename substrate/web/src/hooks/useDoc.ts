import { useCallback, useEffect, useState } from "react";
import { fetchDoc } from "../api/client";
import type { DocResponse } from "../types";

export interface UseDocResult {
    readonly doc: DocResponse | null;
    readonly loading: boolean;
    readonly error: Error | null;
    /**
     * Re-fetch the currently selected document. Useful for file-watcher
     * driven refreshes.
     */
    readonly refresh: () => void;
}

/**
 * Track the currently-selected document. Re-fetches whenever `path`
 * changes (or `refresh()` is called). `path === null` clears state.
 */
export function useDoc(path: string | null): UseDocResult {
    const [doc, setDoc] = useState<DocResponse | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<Error | null>(null);
    const [tick, setTick] = useState(0);

    const refresh = useCallback(() => setTick((t) => t + 1), []);

    useEffect(() => {
        if (path === null) {
            setDoc(null);
            setError(null);
            setLoading(false);
            return;
        }
        let cancelled = false;
        setLoading(true);
        fetchDoc(path)
            .then((d) => {
                if (cancelled) return;
                setDoc(d);
                setError(null);
            })
            .catch((err: unknown) => {
                if (cancelled) return;
                setError(err instanceof Error ? err : new Error(String(err)));
            })
            .finally(() => {
                if (!cancelled) setLoading(false);
            });
        return () => {
            cancelled = true;
        };
    }, [path, tick]);

    return { doc, loading, error, refresh };
}
