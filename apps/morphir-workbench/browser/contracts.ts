import type { Json } from '../../../types/data.ts';
export type { Json } from '../../../types/data.ts';

export interface Diagnostic { message: string; code?: string; severity?: string; }
export interface Artifact { path: string; content: string; binary: boolean; encoding?: string; }
export interface WorkRequest {
  operation: string;
  source?: string;
  sourceBase64?: string;
  sourceCodec?: string;
  arguments?: Json;
  argumentsIon?: string;
  entry?: string;
  languageId?: string;
  target?: string;
  /** A workspace project id for `project`, or the project the local worker compiles; the worker validates it. */
  project?: string | ProjectPayload;
  /** The text files of an `import-folder` request. */
  files?: unknown;
  executionMode?: string;
  /** Historical wire key. Decode into a capability policy before making domain decisions. */
  admission?: Json;
}
/** A project as the browser sends it to the local worker. */
export interface ProjectPayload { files?: unknown; [field: string]: unknown }
export interface Language {
  languageId: string;
  irVersions: string[];
  compile?: boolean;
  fileExtensions?: string[];
}
export interface Target { target: string; irVersions: string[]; generate?: boolean; }
export interface Catalog { frontends: Language[]; targets: Target[]; }
export interface Project { id: string; name: string; projectId?: string; source?: InitialSource; available?: boolean; message?: string; }
export interface WorkResult {
  success: boolean;
  value?: Json;
  typed?: { type: string; value?: Json; [field: string]: Json | undefined };
  terminalOutcomes?: Json;
  /** Untrusted wire selection, checked against the captured capability policy. */
  admission?: Json;
  operation?: string;
  message?: string;
  connected?: boolean;
  capabilityEvaluator?: string;
  catalog?: Catalog;
  frontends?: Language[];
  targets?: Target[];
  projects?: Project[];
  executionsAvailable?: boolean;
  workspaceAvailable?: boolean;
  nativeSession?: boolean;
  cancelled?: boolean;
  ir?: Json;
  irSource?: string;
  generated?: string;
  diagnostics?: Diagnostic[];
  artifacts?: Artifact[];
  originalArtifact?: Artifact;
  inspectionMessage?: string;
  generationMessage?: string;
  execution?: Execution | null;
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
export interface Adapter {
  initialize(): Promise<WorkResult>;
  execute(request: WorkRequest, progress?: Progress): Promise<WorkResult>;
  cancel(): void | Promise<void>;
  dispose(): void;
  runtimeLabel?: string;
  executions?: { active: boolean; execution: Execution | null } | null;
}
export interface InitialSource { providerId: string; locator: string; displayName: string; }
export interface Manifest {
  protocolVersion: number;
  webSocketPath: string;
  sessionId: string;
  providers: { id: string; status: string; capabilities: { name: string; version: string }[] }[];
  initialSources: InitialSource[];
}
export type Core = (command: string) => string;
export interface ExecutionDescriptor {
  profile: string;
  contractVersion: string;
  sessionId?: string;
  operations: string[];
  offer: Json;
}
export interface NativeDescriptor extends ExecutionDescriptor { sessionId: string; }
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
  fetchFn?: Fetch;
  core?: Core;
  pause?: () => Promise<void>;
  authenticate?: () => Promise<string>;
  timeout?: number;
  transport?: ExecutionTransport;
}
export type Invoke = (name: string, source: string) => unknown | Promise<unknown>;
export interface NativeBridge { core?: { invokeOp?: Invoke }; }

export interface NativeOperations {
  'workspace.choose': { cancelled: true } | { cancelled: false; grantId: string; projects: (Project & { available: boolean; message: string })[]; warnings: string[] };
  'workspace.revoke': Record<string, never>;
  'workspace.release': Record<string, never>;
  'workspace.cancel-picker': Record<string, never>;
  'workspace.open': { filename: string; format: string; sequence: number; size: number };
  'workspace.read': { sequence: number; offset: number; content: string; done: boolean };
}

export interface WorkerPort {
  postMessage(message: { id: number; request: WorkRequest }): void;
  terminate(): void;
  onmessage?: ((event: { data: { id: number; result: WorkResult } }) => void) | null;
  onerror?: (() => void) | null;
}
export interface Rpc {
  call(method: string, params: Record<string, unknown>): Promise<unknown>;
  dispose?(): void;
}

export type FetchInit = Omit<RequestInit, 'body'> & { body?: string };
export type Fetch = (url: string, init?: FetchInit) => Promise<Response>;
export type RpcSocket = EventTarget & { readyState: number; send(source: string): void; close(): void; };
