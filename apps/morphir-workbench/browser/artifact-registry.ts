import { isRecord } from '../../../types/data.ts';
import type { Artifact } from './contracts.ts';
import { VerifiedArtifactSet } from './verified-artifacts.ts';

type Selection = { readonly kind: 'empty' } |
  { readonly kind: 'verified'; readonly setId: string; readonly files: VerifiedArtifactSet };
function base64(bytes: Uint8Array): string {
  let encoded = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    encoded += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(encoded);
}

/**
 * The JSON UI carries references and previews; download/ZIP consumers receive
 * fresh original bytes from the private verified owner. Only one current set
 * is retained, so replacing or clearing output invalidates every old handle.
 */
export class ArtifactDownloadRegistry {
  #selection: Selection = { kind: 'empty' };

  clear(): void { this.#selection = { kind: 'empty' }; }

  publish(files: VerifiedArtifactSet): Artifact[] {
    const setId = crypto.randomUUID();
    const previewLimit = Math.min(65536, Math.floor(1048576 / Math.max(1, files.manifest.artifacts.length)));
    const artifacts = files.manifest.artifacts.map(descriptor => {
      const preview = files.preview(descriptor.id);
      const text = preview.kind === 'text' || preview.kind === 'text-prefix' ? preview.text : null;
      let content = text === null ? preview.kind === 'invalid-utf8'
        ? 'Text preview unavailable: this file contains invalid UTF-8. Download preserves the original bytes.' : '' : text.slice(0, previewLimit);
      const last = content.charCodeAt(content.length - 1);
      if (text !== null && last >= 0xd800 && last <= 0xdbff) content = content.slice(0, -1);
      const previewState = text !== null && (preview.kind === 'text-prefix' || text.length > content.length) ? 'text-prefix' as const : preview.kind;
      return {
        path: descriptor.path, binary: descriptor.kind === 'binary',
        content, encoding: 'verified-bytes', byteLength: descriptor.byteLength, previewState,
        // A bounded preview is not a download encoding or an alternate byte owner.
        ...(preview.kind === 'binary' ? { previewBase64: base64(files.previewBytes(descriptor.id).subarray(0, previewLimit)) } : {}),
        verifiedArtifact: { setId, artifactId: descriptor.id },
      } satisfies Artifact;
    });
    this.#selection = { kind: 'verified', setId, files };
    return artifacts;
  }

  bytes(artifacts: readonly unknown[], complete: boolean): Record<string, Uint8Array<ArrayBuffer>> {
    const selected = this.#selection;
    if (selected.kind !== 'verified') throw new Error('These generated files are no longer available. Recompile to download them.');
    if (!artifacts.length || (complete ? artifacts.length !== selected.files.manifest.artifacts.length : artifacts.length !== 1)) {
      throw new Error('The download selection differs from the verified file inventory.');
    }
    const output = Object.create(null) as Record<string, Uint8Array<ArrayBuffer>>;
    const ids = new Set<string>();
    for (const artifact of artifacts) {
      if (!isRecord(artifact) || !isRecord(artifact.verifiedArtifact)) throw new Error('A generated file has no verified byte reference.');
      const reference = artifact.verifiedArtifact;
      if (reference.setId !== selected.setId || typeof reference.artifactId !== 'string' || ids.has(reference.artifactId)) {
        throw new Error('A generated file reference is stale, duplicated or belongs to another output.');
      }
      const descriptor = selected.files.manifest.artifacts.find(file => file.id === reference.artifactId);
      if (!descriptor || artifact.path !== descriptor.path) throw new Error('A generated file reference differs from its verified path.');
      ids.add(descriptor.id);
      output[descriptor.path] = selected.files.bytes(descriptor.id);
    }
    return output;
  }
}

/** Shared only inside the browser bootstrap's module graph. */
export const verifiedArtifactDownloads = new ArtifactDownloadRegistry();
