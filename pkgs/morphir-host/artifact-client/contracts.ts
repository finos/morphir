export type RpcSocket = EventTarget & { readyState: number; send(source: string): void; close(): void; };
