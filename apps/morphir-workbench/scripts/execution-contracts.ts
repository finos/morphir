import type { Worker } from 'node:worker_threads';
import type { CapabilityCheckingOffer, Core, WorkRequest, Json } from '../browser/contracts.ts';

export interface Identity {
  hostId: string; sessionId: string; providerId: string; executionId: string; snapshotId: string;
}
export interface Offer { profile: string; contractVersion: string; hostId: string; sessionId: string; providerId: string; operations: string[]; }
export interface Failure { stage: string; code: string; message: string; }
export interface Outcome { status: string; value?: Json; failure?: Failure; }
export interface Outcomes {
  contractVersion: string; calls: { id: string; outcome: Outcome }[];
  cleanup: Failure | null; extensions: Json;
}
export interface Receipt {
  contractVersion: string; identity: Identity; sequence: number; state: string;
  cancelRequested: boolean; outcomes: Outcomes | null;
}
export interface StrictSubmission { identity: Identity; calls: string[]; receipt: Receipt; plan?: never; }
export interface SchemeExecutionPlan {
  profile: 'morphir/workbench/execution-plan'; contractVersion: '0.2.0-draft.1';
  identity: Identity; planId: string; runtime: 'scheme';
  evaluator: 'scheme-portable-v1/shared-sdk/bounded';
  admission: { profile: 'morphir/workbench/admission'; contractVersion: '0.1.0-draft.1'; policy: 'strict' | 'permissive' };
  boundary: Json;
}
export interface SchemeSubmission { identity: Identity; calls: string[]; receipt: Receipt; plan: SchemeExecutionPlan; }
export type Submission = StrictSubmission | SchemeSubmission;
export type ProviderMapping = 'strict' | 'capability-checks';
export type HostDescriptor = {
  profile: 'morphir/workbench/host'; offer: Offer;
} & ({ contractVersion: '0.2.0-draft.1'; capabilityChecks?: never }
  | { contractVersion: '0.2.0-draft.2'; capabilityChecks: CapabilityCheckingOffer });
export interface SchemeExecutionValues { 'submit-scheme': SchemeSubmission; 'plan-scheme': SchemeExecutionPlan; 'replan-scheme': SchemeSubmission; }
export type SchemeExecutionOperation = keyof SchemeExecutionValues;
export interface ExecutionValues { submit: Submission; query: Receipt; cancel: Receipt; release: { released: boolean }; }
export type ExecutionOperation = keyof ExecutionValues;
export interface ProviderWorker {
  on(type: 'message', listener: (message: { id?: number; result?: { terminalOutcomes?: Outcomes; executionPlan?: SchemeExecutionPlan } }) => void): unknown;
  on(type: 'error', listener: (error: Error) => void): unknown;
  once(type: 'exit', listener: (code: number) => void): unknown;
  postMessage(message: unknown): void;
  terminate(): Promise<number>;
}
export interface ProviderOptions {
  mapping?: ProviderMapping;
  bridgeUrl?: URL; workerUrl?: URL; deadlineMs?: number;
  factory?: (source: string) => Core; workerFactory?: () => ProviderWorker; decoder?: Core;
}
export interface ExecutionProvider {
  decode(source: string): unknown;
  session(sessionId: string): Promise<HostDescriptor>;
  command<K extends ExecutionOperation>(operation: K, body: string, sessionId: string): Promise<ExecutionValues[K]>;
  /** Private policy-aware path. Not advertised by HTTP/native descriptors. */
  schemeCommand<K extends SchemeExecutionOperation>(operation: K, body: string, sessionId: string): Promise<SchemeExecutionValues[K]>;
  close(): Promise<void>;
}
export interface ExecutionRecord {
  identity: Identity; done: boolean; worker: ProviderWorker | null;
  selection: { mode: 'whole-model' } | { mode: 'selected-scheme'; plan: SchemeExecutionPlan };
  failure?: unknown; captured?: Outcomes | null; stopReason?: string;
  stopping?: Promise<number>; finished?: boolean; timer?: ReturnType<typeof setTimeout>; exited?: Promise<void>;
  selectionMismatch?: boolean;
}
export type Claim = WorkRequest;

/** The HTTP gateway forwards admitted frames without interpreting execution outcomes. */
export interface ExecutionGateway {
  decode(source: string): unknown;
  session(sessionId: string): Promise<unknown>;
  command(operation: ExecutionOperation, source: string, sessionId: string): Promise<unknown>;
  close(): void | Promise<void>;
}
