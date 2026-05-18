/**
 * Thin typed client for the substrate dev HTTP API. All endpoints are
 * served by the same origin (Vite proxies them in dev, substrate dev
 * serves them directly in prod).
 */
import type { DocResponse, TreeNode } from "../types";

async function getJSON<T>(url: string): Promise<T> {
    const res = await fetch(url);
    if (!res.ok) {
        throw new Error(`${url} → ${res.status} ${res.statusText}`);
    }
    return (await res.json()) as T;
}

export function fetchTree(): Promise<TreeNode> {
    return getJSON<TreeNode>("/api/tree");
}

export function fetchDoc(path: string): Promise<DocResponse> {
    return getJSON<DocResponse>(`/api/doc?path=${encodeURIComponent(path)}`);
}

/** URL for the file-watcher WebSocket on the same origin as the page. */
export function wsUrl(): string {
    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    return `${proto}://${window.location.host}/_ws`;
}
