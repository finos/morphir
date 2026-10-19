import type { Json } from '../../../types/data.ts';
export type { Json } from '../../../types/data.ts';

export interface WorkRequest {
  source?: string; entry?: string; arguments?: Json; argumentsIon?: string;
  executionMode?: string; admission?: Json;
}
export interface WorkResult {
  success: boolean; terminalOutcomes?: Json; execution?: Execution | null;
  typed?: { type: string; value?: Json; [field: string]: Json | undefined };
  value?: Json; admission?: Json; executionPlan?: Json;
}
export interface Execution {
  state: 'submitted' | 'running' | 'terminal';
  identity: { hostId: string; sessionId: string; providerId: string; executionId: string; snapshotId: string };
  connected?: boolean;
  sequence?: number;
  cancelRequested?: boolean;
  cancelAction?: 'send' | 'pending' | 'already-terminal' | 'unavailable' | 'disconnected';
}
export type Progress = (execution: Execution | null) => void;
export type Core = (command: string) => string;
export interface ExecutionDescriptor {
  capabilityChecks?: CapabilityCheckingOffer;
  profile: string;
  contractVersion: string;
  sessionId?: string;
  operations: string[];
  offer: Json;
}
/** An explicit contract selection. No protocol downgrade follows a failed handshake. */
export type NativeMapping = 'executions' | 'capability-checks';
export interface CapabilityCheckingOffer {
  profile: 'morphir/workbench/admission';
  contractVersion: '0.1.0-draft.1';
  runtime: 'scheme';
  evaluator: 'scheme-portable-v1/shared-sdk/bounded';
  policies: ['strict', 'permissive'];
}
export interface NativeDescriptor extends ExecutionDescriptor { sessionId: string; capabilityChecks?: CapabilityCheckingOffer; }
export type NativeReply<T> = { ok: true; operation: string; value: T } |
  { ok: false; error: { code: string; message: string; effect: string } };
export interface CoreReply<T = Json> {
  ok: boolean;
  code?: string;
  value: T;
  execution?: Execution;
  result?: WorkResult;
}
export interface ExecutionTransport {
  request?(path: string, source?: string, optional?: boolean): Promise<{ ok: boolean; status: number; source: string }>;
  nativeDescriptor?(): Promise<string>;
  nativeRequest?(source: string): Promise<string>;
}
export interface ExecutionOptions {
  nativeMapping?: NativeMapping;
  /** Trusted diagnostics hook. The client retains only its current accepted plan. */
  onAcceptedPlan?: (plan: Json) => void;
  fetchFn?: Fetch;
  core?: Core;
  pause?: () => Promise<void>;
  authenticate?: () => Promise<string>;
  timeout?: number;
  transport?: ExecutionTransport;
}
export type FetchInit = Omit<RequestInit, 'body'> & { body?: string };
export type Fetch = (url: string, init?: FetchInit) => Promise<Response>;
