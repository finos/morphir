import { isRecord } from '../../../types/data.ts';
import type { WorkRequest } from './contracts.ts';

export type CapabilityPolicy = 'strict' | 'permissive';

/** A decoded, immutable selection, independent of the caller's mutable request. */
export type LocalEvaluation =
  | { readonly kind: 'legacy' }
  | { readonly kind: 'capability'; readonly policy: CapabilityPolicy };

/** Compatibility codec for the existing wire profile. */
export function decodeCapabilityPolicy(value: unknown): CapabilityPolicy | null {
  if (!isRecord(value) || Object.keys(value).length !== 3
      || value.profile !== 'morphir/workbench/admission' || value.contractVersion !== '0.1.0-draft.1') return null;
  return value.policy === 'strict' || value.policy === 'permissive' ? value.policy : null;
}

export function captureLocalEvaluation(request: WorkRequest): LocalEvaluation {
  if (request.executionMode !== 'capability') return { kind: 'legacy' };
  const policy = request.admission == null ? 'strict' : decodeCapabilityPolicy(request.admission);
  if (policy === null) throw new Error('The local request has an invalid capability checking policy.');
  return { kind: 'capability', policy };
}

export function matchesCapabilityPolicy(selection: LocalEvaluation, value: unknown): boolean {
  return selection.kind === 'legacy' || decodeCapabilityPolicy(value) === selection.policy;
}
