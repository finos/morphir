import type { Json } from '../../../types/data.ts';
import { workbenchError } from '../../../types/data.ts';
import {
  ARTIFACT_CONTRACT_VERSION, ARTIFACT_LIMITS, ARTIFACT_METHODS,
  artifactChunkBytes, captureArtifactGeneration, captureArtifactRead, captureArtifactRelease,
  decodeArtifactGenerateReply, decodeArtifactReadReply, decodeArtifactReleaseReply,
  encodeArtifactReadRequest, encodeArtifactReleaseRequest, parseArtifactRequestId,
  type ArtifactClientFailure, type ArtifactDiagnostic, type ArtifactGenerationCapture,
  type ArtifactGenerationId, type ArtifactId, type ArtifactProfileSelection, type ArtifactResult,
  type GeneratedArtifactManifest,
} from './artifact-client/artifact-transfer.ts';
import { wellFormed } from './artifact-client/artifact-wire.ts';
import { VerifiedArtifactSet, type ArtifactVerificationEffects } from './verified-artifacts.ts';

/** A dedicated, already-open connection belonging only to this attempt. */
export interface ArtifactExchange {
  readonly closed: boolean;
  exchange(source: string): Promise<string>;
  close(): void;
}
export interface ArtifactTransferEffects extends ArtifactVerificationEffects {
  connect(signal: AbortSignal): Promise<ArtifactExchange>;
}
export interface ArtifactGenerationInput {
  readonly sessionId: string;
  readonly target: string;
  readonly irVersion: string;
  readonly ir: Json;
  readonly options: Json;
}
export type ArtifactCleanup =
  | { readonly kind: 'not-connected' }
  | { readonly kind: 'not-retained' }
  | { readonly kind: 'released'; readonly generationId: ArtifactGenerationId }
  | { readonly kind: 'connection-closed'; readonly generationId: ArtifactGenerationId | null;
      readonly reason: 'pending-exchange' | 'unknown-retention' | 'release-failed' };
export type ArtifactTransferResult =
  | { readonly kind: 'verified'; readonly files: VerifiedArtifactSet; readonly cleanup: ArtifactCleanup }
  | { readonly kind: 'generation-failed'; readonly diagnostics: readonly ArtifactDiagnostic[]; readonly cleanup: ArtifactCleanup }
  | { readonly kind: 'failed'; readonly error: Error; readonly cleanup: ArtifactCleanup }
  | { readonly kind: 'discarded'; readonly cleanup: ArtifactCleanup };
export type ArtifactTransferPhase =
  'captured' | 'connecting' | 'initializing' | 'generating' | 'receiving' | 'verifying' | 'releasing' | 'finished';

type ReadyConnection =
  | { readonly kind: 'connected'; readonly channel: ArtifactExchange }
  | { readonly kind: 'retained'; readonly channel: ArtifactExchange; readonly manifest: GeneratedArtifactManifest };
type Resource =
  | { readonly kind: 'unconnected' }
  | ReadyConnection
  | { readonly kind: 'exchanging'; readonly channel: ArtifactExchange; readonly manifest: GeneratedArtifactManifest | null }
  | { readonly kind: 'releasing'; readonly completion: Promise<ArtifactCleanup> }
  | { readonly kind: 'closed'; readonly cleanup: ArtifactCleanup };

export type ArtifactInputFailure = 'ill-formed-unicode' | 'nonfinite-number' | 'request-limit';
const inputMessages: Record<ArtifactInputFailure, string> = {
  'ill-formed-unicode': 'Artifact input contains ill-formed Unicode.',
  'nonfinite-number': 'Artifact input contains a nonfinite number.',
  'request-limit': 'The artifact generation request exceeds the complete 1 MiB frame limit.',
};
export class ArtifactInputError extends Error {
  readonly reason: ArtifactInputFailure;
  constructor(reason: ArtifactInputFailure) { super(inputMessages[reason]); this.reason = reason; }
}

export class ArtifactTransferProtocolError extends Error {
  readonly failure: ArtifactClientFailure;
  constructor(failure: ArtifactClientFailure) {
    super(`Artifact transfer refused: ${failure.code}`);
    this.failure = failure;
  }
}
function accepted<T>(result: ArtifactResult<T>): T {
  if (!result.ok) throw new ArtifactTransferProtocolError(result.error);
  return result.value;
}
class ObsoleteArtifactTransfer extends Error {}

/**
 * One captured input, one producer invocation, one owning connection. No output
 * escapes until every file verifies and the exact generation is released.
 * Legacy initialization is the only parsed control reply; artifact replies go
 * directly from raw text to the upstream literal-preserving decoders.
 */
export class ArtifactTransferAttempt {
  readonly capture: ArtifactGenerationCapture;
  readonly #generateSource: string;
  readonly #effects: ArtifactTransferEffects;
  readonly #abort = new AbortController();
  #resource: Resource = { kind: 'unconnected' };
  #phase: ArtifactTransferPhase = 'captured';
  #nextId = 2;

  constructor(selection: ArtifactProfileSelection, input: ArtifactGenerationInput, effects: ArtifactTransferEffects) {
    this.capture = accepted(captureArtifactGeneration(selection, input));
    // Serialize before any async effect. Caller mutations cannot alter this attempt.
    // JSON escaping does not make a lone surrogate a valid Unicode scalar.
    // Reject nonfinite values too, instead of silently turning them into null.
    this.#generateSource = JSON.stringify({ jsonrpc: '2.0', id: 2, method: ARTIFACT_METHODS.generate, params: {
      contractVersion: ARTIFACT_CONTRACT_VERSION, providerId: this.capture.selection.providerId,
      generation: { ir: input.ir, irVersion: this.capture.irVersion, target: this.capture.target, options: input.options },
    } }, (key, value: unknown) => {
      if (!wellFormed(key) || typeof value === 'string' && !wellFormed(value)) {
        throw new ArtifactInputError('ill-formed-unicode');
      }
      if (typeof value === 'number' && !Number.isFinite(value)) throw new ArtifactInputError('nonfinite-number');
      return value;
    });
    if (new TextEncoder().encode(this.#generateSource).byteLength > ARTIFACT_LIMITS.generateRequestBytes) {
      throw new ArtifactInputError('request-limit');
    }
    this.#effects = {
      connect: effects.connect.bind(effects), isCurrent: effects.isCurrent.bind(effects),
      ...(effects.digest ? { digest: effects.digest.bind(effects) } : {}),
    };
  }

  get phase(): ArtifactTransferPhase { return this.#phase; }
  #current = () => !this.#abort.signal.aborted && this.#effects.isCurrent();
  #reconcile() { if (!this.#current()) throw new ObsoleteArtifactTransfer(); }
  #requestId() { return accepted(parseArtifactRequestId(++this.#nextId)); }

  async #exchange(source: string): Promise<string> {
    const connection = this.#resource;
    if (connection.kind !== 'connected' && connection.kind !== 'retained') throw new Error('Artifact connection is unavailable.');
    const pending: Resource = { kind: 'exchanging', channel: connection.channel,
      manifest: connection.kind === 'retained' ? connection.manifest : null };
    this.#resource = pending;
    try { return await connection.channel.exchange(source); }
    finally { if (this.#resource === pending) this.#resource = connection; }
  }

  /** Synchronous cancellation starts bounded cleanup even while a digest is pending. */
  cancel(): Promise<ArtifactCleanup> {
    this.#abort.abort();
    return this.#cleanup();
  }

  #cleanup(): Promise<ArtifactCleanup> {
    const resource = this.#resource;
    if (resource.kind === 'closed') return Promise.resolve(resource.cleanup);
    if (resource.kind === 'releasing') return resource.completion;
    if (resource.kind === 'retained' && !resource.channel.closed) {
      this.#phase = 'releasing';
      // Install the single cleanup owner before sending, including synchronous test ports.
      const completion = Promise.resolve().then(async (): Promise<ArtifactCleanup> => {
        const capture = captureArtifactRelease(resource.manifest);
        const id = this.#requestId();
        try {
          const source = accepted(encodeArtifactReleaseRequest(capture, id));
          const reply = await resource.channel.exchange(source);
          accepted(decodeArtifactReleaseReply(reply, capture, id));
          return { kind: 'released', generationId: resource.manifest.generationId };
        } catch {
          return { kind: 'connection-closed', generationId: resource.manifest.generationId, reason: 'release-failed' };
        } finally { resource.channel.close(); }
      }).then(cleanup => { this.#resource = { kind: 'closed', cleanup }; return cleanup; });
      this.#resource = { kind: 'releasing', completion };
      return completion;
    }
    let cleanup: ArtifactCleanup;
    if (resource.kind === 'unconnected') cleanup = { kind: 'not-connected' };
    else {
      resource.channel.close();
      cleanup = { kind: 'connection-closed',
        generationId: resource.kind === 'retained' ? resource.manifest.generationId :
          resource.kind === 'exchanging' ? resource.manifest?.generationId ?? null : null,
        reason: resource.kind === 'exchanging' ? 'pending-exchange' : 'unknown-retention' };
    }
    this.#resource = { kind: 'closed', cleanup };
    return Promise.resolve(cleanup);
  }

  async run(): Promise<ArtifactTransferResult> {
    if (this.#phase !== 'captured') throw new Error('An artifact attempt can run only once.');
    try {
      this.#reconcile();
      this.#phase = 'connecting';
      const channel = await this.#effects.connect(this.#abort.signal);
      // A connect implementation may finish after cancellation. It still owns no other attempt.
      this.#resource = { kind: 'connected', channel };
      this.#reconcile();
      this.#phase = 'initializing';
      const initialized: unknown = JSON.parse(await this.#exchange(JSON.stringify({ jsonrpc: '2.0', id: 1,
        method: 'morphir.session.initialize', params: { protocolVersion: 1, sessionId: this.capture.sessionId } })));
      this.#reconcile();
      if (!initialized || typeof initialized !== 'object' || Array.isArray(initialized) ||
          !('jsonrpc' in initialized) || initialized.jsonrpc !== '2.0' ||
          !('id' in initialized) || initialized.id !== 1 || 'error' in initialized ||
          !('result' in initialized) || !initialized.result || typeof initialized.result !== 'object' ||
          !('protocolVersion' in initialized.result) || initialized.result.protocolVersion !== 1) {
        throw new Error('The artifact connection did not initialize protocol v1.');
      }
      this.#phase = 'generating';
      const generated = accepted(decodeArtifactGenerateReply(await this.#exchange(this.#generateSource),
        this.capture, accepted(parseArtifactRequestId(2))));
      // Learn the exact retained identity before reconciling an obsolete but valid manifest.
      if (generated.status === 'ready' && this.#resource.kind === 'connected') {
        this.#resource = { kind: 'retained', channel, manifest: generated };
      }
      this.#reconcile();
      if (generated.status === 'failed') {
        channel.close();
        const cleanup: ArtifactCleanup = { kind: 'not-retained' };
        this.#resource = { kind: 'closed', cleanup };
        return { kind: 'generation-failed', diagnostics: generated.diagnostics, cleanup };
      }
      const bytes = new Map<ArtifactId, Uint8Array>();
      this.#phase = 'receiving';
      for (const artifact of generated.artifacts) {
        const received = new Uint8Array(artifact.byteLength);
        // Read empty files once as well, so the producer must honor the advertised handle.
        let offset = 0;
        do {
          const read = accepted(captureArtifactRead(generated, artifact.id, offset, ARTIFACT_LIMITS.chunkBytes));
          const id = this.#requestId();
          const reply = await this.#exchange(accepted(encodeArtifactReadRequest(read, id)));
          this.#reconcile();
          const chunk = accepted(decodeArtifactReadReply(reply, read, id));
          received.set(artifactChunkBytes(chunk), offset);
          offset = chunk.nextOffset;
        } while (offset < artifact.byteLength);
        bytes.set(artifact.id, received);
      }
      this.#phase = 'verifying';
      const files = await VerifiedArtifactSet.verify(generated, bytes, { ...this.#effects, isCurrent: this.#current });
      this.#reconcile();
      const cleanup = await this.#cleanup();
      this.#reconcile();
      if (cleanup.kind !== 'released') throw new Error('Artifact bytes verified, but release failed. The owning connection was closed.');
      return { kind: 'verified', files, cleanup };
    } catch (cause) {
      const cleanup = await this.#cleanup();
      if (!this.#current()) return { kind: 'discarded', cleanup };
      return { kind: 'failed', error: workbenchError(cause), cleanup };
    } finally { this.#phase = 'finished'; }
  }
}
