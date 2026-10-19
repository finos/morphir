import type { ArtifactId, GeneratedArtifactDescriptor, GeneratedArtifactManifest } from './artifact-client/artifact-transfer.ts';

export type ArtifactPreview =
  | { readonly kind: 'text'; readonly text: string }
  | { readonly kind: 'text-prefix'; readonly text: string }
  | { readonly kind: 'binary' }
  | { readonly kind: 'invalid-utf8' };

export interface ArtifactVerificationEffects {
  readonly isCurrent: () => boolean;
  /** Trusted cryptographic effect; receives a separate copy of the owned bytes. */
  readonly digest?: (bytes: ArrayBuffer) => Promise<ArrayBuffer>;
}

type VerificationFailure = 'obsolete' | 'inventory' | 'length' | 'digest' | 'digest-unavailable';
const messages: Record<VerificationFailure, string> = {
  obsolete: 'This artifact verification belongs to an obsolete request.',
  inventory: 'The received file inventory differs from the captured manifest.',
  length: 'A received file length differs from the captured manifest.',
  digest: 'A received file digest differs from the captured manifest.',
  'digest-unavailable': 'Artifact digest verification failed.',
};
export class ArtifactVerificationError extends Error {
  readonly reason: VerificationFailure;
  constructor(reason: VerificationFailure, options?: ErrorOptions) {
    super(messages[reason], options);
    this.reason = reason;
  }
}

const verified = Symbol('complete artifact byte verification');
const sha256 = (bytes: ArrayBuffer) => crypto.subtle.digest('SHA-256', bytes);
const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map(value => value.toString(16).padStart(2, '0')).join('');
type OwnedFile = { readonly descriptor: GeneratedArtifactDescriptor; readonly bytes: Uint8Array<ArrayBuffer> };

/**
 * A complete captured generation whose privately owned original bytes passed
 * length and SHA-256 checks. No verified prefix escapes a failed set. A caller
 * still reconciles its attempt after awaiting this factory and host release.
 */
export class VerifiedArtifactSet {
  readonly manifest: GeneratedArtifactManifest;
  #files: ReadonlyMap<ArtifactId, OwnedFile>;

  private constructor(key: typeof verified, manifest: GeneratedArtifactManifest, files: ReadonlyMap<ArtifactId, OwnedFile>) {
    if (key !== verified) throw new Error('Artifact byte verification is required.');
    this.manifest = manifest;
    this.#files = files;
    Object.freeze(this);
  }

  static async verify(
    manifest: GeneratedArtifactManifest,
    received: ReadonlyMap<ArtifactId, Uint8Array>,
    effects: ArtifactVerificationEffects,
  ): Promise<VerifiedArtifactSet> {
    const current = effects.isCurrent.bind(effects);
    const digest = (effects.digest ?? sha256).bind(effects);
    const reconcile = () => { if (!current()) throw new ArtifactVerificationError('obsolete'); };
    reconcile();
    if (received.size !== manifest.artifacts.length) throw new ArtifactVerificationError('inventory');
    const files = new Map<ArtifactId, OwnedFile>();
    // Capture the entire caller-owned input before the first awaited hash.
    for (const descriptor of manifest.artifacts) {
      const source = received.get(descriptor.id);
      if (!(source instanceof Uint8Array)) throw new ArtifactVerificationError('inventory');
      if (source.byteLength !== descriptor.byteLength) throw new ArtifactVerificationError('length');
      files.set(descriptor.id, Object.freeze({ descriptor, bytes: new Uint8Array(source) }));
    }
    for (const file of files.values()) {
      let measured: ArrayBuffer;
      try { measured = await digest(file.bytes.slice().buffer); }
      catch (cause) {
        reconcile();
        throw new ArtifactVerificationError('digest-unavailable', { cause });
      }
      reconcile();
      if (!(measured instanceof ArrayBuffer) || measured.byteLength !== 32 || hex(measured) !== file.descriptor.sha256) {
        throw new ArtifactVerificationError('digest');
      }
    }
    reconcile();
    return new VerifiedArtifactSet(verified, manifest, files);
  }

  /** Fresh bytes keep preview, ZIP and download consumers from mutating the owner. */
  bytes(id: ArtifactId): Uint8Array<ArrayBuffer> {
    const file = this.#files.get(id);
    if (!file) throw new ArtifactVerificationError('inventory');
    return file.bytes.slice();
  }

  /** Bounded hex previews need no full-file copy or second byte owner. */
  previewBytes(id: ArtifactId): Uint8Array<ArrayBuffer> {
    const file = this.#files.get(id);
    if (!file) throw new ArtifactVerificationError('inventory');
    return file.bytes.slice(0, 65536);
  }

  preview(id: ArtifactId): ArtifactPreview {
    const file = this.#files.get(id);
    if (!file) throw new ArtifactVerificationError('inventory');
    if (file.descriptor.kind === 'binary') return Object.freeze({ kind: 'binary' });
    try {
      const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
      let text = ''; let length = 0;
      const accept = (piece: string) => {
        length += piece.length;
        if (text.length < 65536) text += piece.slice(0, 65536 - text.length);
      };
      // Validate the whole file, including bytes beyond the bounded UI prefix.
      for (let offset = 0; offset < file.bytes.length; offset += 65536) {
        accept(decoder.decode(file.bytes.subarray(offset, offset + 65536), { stream: true }));
      }
      accept(decoder.decode());
      if (length <= 65536) return Object.freeze({ kind: 'text', text });
      // A prefix never ends halfway through a Unicode scalar's UTF-16 representation.
      const last = text.charCodeAt(text.length - 1);
      if (last >= 0xd800 && last <= 0xdbff) text = text.slice(0, -1);
      return Object.freeze({ kind: 'text-prefix', text });
    } catch { return Object.freeze({ kind: 'invalid-utf8' }); }
  }
}
