import { useEffect, useRef, useState } from "react";
import { wsUrl } from "../api/client";
import type { WsMessage } from "../types";

export type LiveStatus = "connecting" | "connected";

/**
 * Open a WebSocket to the substrate file watcher and call `onMessage`
 * for every event. Automatically reconnects with exponential backoff.
 *
 * `onMessage` is captured via a ref so callers don't have to memoise
 * it — that keeps consumers simple even as the app grows.
 */
export function useLiveReload(
    onMessage: (msg: WsMessage) => void,
): LiveStatus {
    const [status, setStatus] = useState<LiveStatus>("connecting");
    const handlerRef = useRef(onMessage);
    handlerRef.current = onMessage;

    useEffect(() => {
        let cancelled = false;
        let backoff = 500;
        let socket: WebSocket | null = null;

        function connect(): void {
            if (cancelled) return;
            const ws = new WebSocket(wsUrl());
            socket = ws;
            ws.addEventListener("open", () => {
                setStatus("connected");
                backoff = 500;
            });
            ws.addEventListener("close", () => {
                setStatus("connecting");
                setTimeout(connect, backoff);
                backoff = Math.min(backoff * 2, 5000);
            });
            ws.addEventListener("error", () => ws.close());
            ws.addEventListener("message", (ev: MessageEvent<string>) => {
                try {
                    const msg = JSON.parse(ev.data) as WsMessage;
                    handlerRef.current(msg);
                } catch {
                    // Ignore non-JSON frames.
                }
            });
        }

        connect();
        return () => {
            cancelled = true;
            socket?.close();
        };
    }, []);

    return status;
}
