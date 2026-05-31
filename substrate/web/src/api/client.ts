/**
 * Thin typed client for the substrate dev HTTP API. All endpoints are
 * served by the same origin (Vite proxies them in dev, substrate dev
 * serves them directly in prod).
 */
import type {
    DocResponse,
    IRResponse,
    SimplifiedIRResponse,
    TreeNode,
} from "../types";

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

let cachedIR: IRResponse | undefined;

/**
 * Fetch the Morphir IR from `/api/ir`.  The result is cached in memory so
 * repeated calls during a single page-load don't re-fetch.  Pass
 * `{ bust: true }` to force a fresh request (e.g. after a file-change WS
 * event indicates `morphir.json` was updated).
 */
export async function fetchIR({ bust = false }: { bust?: boolean } = {}): Promise<IRResponse> {
    if (!bust && cachedIR !== undefined) return cachedIR;
    cachedIR = await getJSON<IRResponse>("/api/ir");
    return cachedIR;
}

let cachedSimplifiedIR: SimplifiedIRResponse | undefined;

/** Fetch the simplified IR distribution as a list of per-module files. */
export async function fetchSimplifiedIR(
    { bust = false }: { bust?: boolean } = {},
): Promise<SimplifiedIRResponse> {
    if (!bust && cachedSimplifiedIR !== undefined) return cachedSimplifiedIR;
    cachedSimplifiedIR = await getJSON<SimplifiedIRResponse>("/api/simplified-ir");
    return cachedSimplifiedIR;
}

/** URL for the file-watcher WebSocket on the same origin as the page. */
export function wsUrl(): string {
    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    return `${proto}://${window.location.host}/_ws`;
}
