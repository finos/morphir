/** Opaque JSON data at transport and compiler boundaries. */
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export interface WorkbenchError extends Error {
  code?: string;
  status?: number;
  effect?: string;
  native?: boolean;
  rejected?: boolean;
  execution?: unknown;
  executionTransport?: boolean;
  submissionUnknown?: boolean;
  diagnostics?: unknown[];
}

/** Preserve Error identity and attached evidence when a host operation throws. */
export function workbenchError(cause: unknown): WorkbenchError {
  return cause instanceof Error ? cause : new Error(String(cause));
}
