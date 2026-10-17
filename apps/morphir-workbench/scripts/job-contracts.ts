import type { Worker } from 'node:worker_threads';
import type { Core, WorkRequest, Json } from '../browser/contracts.ts';

export interface Identity {
  hostId: string; sessionId: string; providerId: string; jobId: string; snapshotId: string;
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
export interface Submission { identity: Identity; calls: string[]; receipt: Receipt; }
export interface SchemeJobPlan {
  profile: 'morphir/workbench/job-plan'; contractVersion: '0.1.0-draft.1';
  identity: Identity; planId: string; runtime: 'scheme';
  evaluator: 'scheme-portable-v1/shared-sdk/bounded';
  admission: { profile: 'morphir/workbench/admission'; contractVersion: '0.1.0-draft.1'; policy: 'strict' | 'permissive' };
  boundary: Json;
}
export interface SchemeSubmission extends Submission { plan: SchemeJobPlan; }
export interface SchemeJobValues { 'submit-scheme': SchemeSubmission; 'plan-scheme': SchemeJobPlan; 'replan-scheme': SchemeSubmission; }
export type SchemeJobOperation = keyof SchemeJobValues;
export interface JobValues { submit: Submission; query: Receipt; cancel: Receipt; release: { released: boolean }; }
export type JobOperation = keyof JobValues;
export interface ProviderWorker {
  on(type: 'message', listener: (message: { id?: number; result?: { terminalOutcomes?: Outcomes; jobPlan?: SchemeJobPlan } }) => void): unknown;
  on(type: 'error', listener: (error: Error) => void): unknown;
  once(type: 'exit', listener: (code: number) => void): unknown;
  postMessage(message: unknown): void;
  terminate(): Promise<number>;
}
export interface ProviderOptions {
  bridgeUrl?: URL; workerUrl?: URL; deadlineMs?: number;
  factory?: (source: string) => Core; workerFactory?: () => ProviderWorker; decoder?: Core;
}
export interface JobProvider {
  decode(source: string): unknown;
  session(sessionId: string): Promise<{ profile: string; contractVersion: string; offer: Offer }>;
  command<K extends JobOperation>(operation: K, body: string, sessionId: string): Promise<JobValues[K]>;
  /** Private policy-aware path. Not advertised by HTTP/native descriptors. */
  schemeCommand<K extends SchemeJobOperation>(operation: K, body: string, sessionId: string): Promise<SchemeJobValues[K]>;
  close(): Promise<void>;
}
export interface JobRecord {
  identity: Identity; done: boolean; worker: ProviderWorker | null;
  failure?: unknown; captured?: Outcomes | null; stopReason?: string;
  stopping?: Promise<number>; finished?: boolean; timer?: ReturnType<typeof setTimeout>; exited?: Promise<void>;
  schemePlan?: SchemeJobPlan; selectionMismatch?: boolean;
}
export type Claim = WorkRequest;

/** The HTTP gateway forwards admitted frames without interpreting job outcomes. */
export interface JobGateway {
  decode(source: string): unknown;
  session(sessionId: string): Promise<unknown>;
  command(operation: JobOperation, source: string, sessionId: string): Promise<unknown>;
  close(): void | Promise<void>;
}
