import type { Outcomes } from '../apps/morphir-workbench/scripts/job-contracts.ts';
import type { Json } from '../types/data.ts';

declare global {
  var artifactDownload: { name: string; bytes: number[] } | null;
  var toolKeys: boolean[];
  var nativeJobCalls: string[];
  var workspaceDownload: Promise<number[]>;
  var releaseEvaluation: (() => void) | undefined;
  var restoreRequests: (() => void) | undefined;
  var releaseTyped: (() => void) | undefined;
  var restoreTyped: (() => void) | undefined;
  var releaseLocalScopeReply: (() => void) | undefined;
  var restoreLocalScopeRequests: (() => void) | undefined;
  var releaseTerminalReply: (() => void) | undefined;
  var restoreTerminalRequests: (() => void) | undefined;
  var holdTerminalReply: boolean | undefined;
  var terminalFixture: { success: boolean; profile: string; typed: Json; value: string; terminalOutcomes: Outcomes } | undefined;
}
