import type { SpawnSyncReturns } from 'node:child_process';
import type { BuildEvidence } from '../apps/morphir/build-provider/contracts.mjs';
import type { Json } from '../types/data.ts';

export interface RunOptions { cwd?: string; status?: number | null; env?: NodeJS.ProcessEnv; }
export type Run = (program: string, args: string[], options?: RunOptions) => SpawnSyncReturns<string>;
export interface InstalledContext {
  run: Run; root: string; receipts: string; cli: string; helper: string; cwd: string; home: string;
  llvmHome?: string; llvmPin?: string; required: string[]; deps: string[]; pack: { integrity: string }; repo?: string;
}
export interface Value { type: string; value?: Json; [field: string]: Json | undefined; }
export interface Call {
  id: string; status: string; actual: Value; expected: Value | null;
  reason?: string; matches: boolean | null; mismatchPath: string; failure?: { code: string; message: string };
}
export interface Coverage { provider: string; required: boolean; calls: Call[]; evidence: Record<string, Json>; }
export interface VerificationReport {
  successful: boolean; cancelled: boolean; target: string;
  failure?: { cause: string; cleanup: string | null };
  comparison: { profile: string }; extensions: { format: string }; calls: Call[];
  terminals: { id: string; status: string }[]; evidence: BuildEvidence;
  invocationEvidence: { suiteIdentity: string };
}
export interface ConformanceReport {
  successful: boolean; cancelled: boolean; dryRun: boolean; calls: Call[];
  coverage: Coverage[]; execution: VerificationReport; entries: string[];
}
export interface Observation {
  profile: string; stage: string; signal: string; duration_seconds: number;
  trace_id: string; span_id: string; parent_id: string;
  correlation: { target: string; lease_id: string; attempt_id: string };
  details?: { code?: string };
}
export interface Warning {
  path: string; code: string; fix: string;
  locations: { owner: string; original: string; allocated: string; source: { startLine: number } }[];
}
export interface PipelineReport {
  successful: boolean; processed: number; publicationError: string | null;
  projects: unknown[]; committed: unknown[]; error: string;
  warnings: Warning[]; diagnostics: { message: string }[];
  frontends: FrontendInventory[]; boundaries: Record<string, Json>[];
}
export interface Frame { type: string; data: PipelineReport & ConformanceReport; }
export interface FixtureEntry { original: string; semantic: string; arguments: boolean[][]; expected: boolean[]; }
export interface LibraryModel { id: string; source: string; entries: FixtureEntry[]; private: { original: string }[]; }
export interface LibraryFixtures { profile: string; language: string; parserVersion: string; models: LibraryModel[]; }
export interface Generated { module: string; manifest: string; artifacts: { path: string; content: string | number[]; binary: boolean }[]; }
export interface NamingModel {
  id: string; source: string; entries: FixtureEntry[];
  checkpoints: { binary: number[]; text: string }; generated: Generated; legacyGenerated: Generated;
  opaqueCheckpoints: { binary: number[]; text: string }; opaqueGenerated: Generated;
}
export interface NamingFixtures {
  profile: string; provider: string; language: string; parserVersion: string; frontendPolicy: string; backendPolicy: string;
  models: NamingModel[]; requests: { format: string; checkpoint: number[]; generated: Generated; legacyGenerated: Generated }[];
}
export interface NamingRow { id: string; original: string; entry: string; arguments: boolean[]; expected: boolean; }

/** Test expectations supply the contract; production admission stays in codecs. */
export function parse<T>(source: string): T { return JSON.parse(source); }
export function observations(source: string): Observation[] { return source.trim().split('\n').map(line => parse<Observation>(line)); }

export interface FrontendInventory {
  [field: string]: Json;
  source: string; unitId: string; frontend: string; profile: string; language: string; provider: string;
  defaultProfile: boolean; evidence: string; outputContract: string; availableProfiles: string[];
  dependencies: Record<string,string>;
  capabilities: { maxDocuments: number; incremental: boolean; limits: Record<string,number> };
}
export interface Visibility { model: LibraryModel; original: string; generated: string; canonical: (name: string) => string; }
export interface Consumer { id: string; path: string; module: string; rows: { id: string; function: string; arguments: boolean[]; expected: boolean }[]; }

export interface SeedModel { id: string; source: string; function: string; expected: boolean[]; scheme: boolean[]; module: string; artifacts: Generated['artifacts']; ir: string; }
export interface LoweredModel extends Omit<SeedModel,'function' | 'expected' | 'scheme'> {
  entries: (FixtureEntry & { function: string; scheme: boolean[] })[];
  private: { original: string; function: string }[];
}
