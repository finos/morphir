import {
  ARTIFACT_PROFILE, ARTIFACT_CONTRACT_VERSION, selectArtifactTransferProfile,
} from './artifact-client/artifact-transfer.ts';
import {refuse} from '../connection/node-session.mts';
import type {Manifest} from '../execution-client/manifest.mts';
import type {Json} from '../execution-client/contracts.mts';

/** Pin exactly one qualified owner; a catalog or MEP offer cannot replace it. */
export function artifactConnectionDescriptor(manifest: Manifest): Json {
  const providers = manifest.providers.filter(provider => provider.status === 'available' &&
    provider.capabilities.some(offer => offer.name === ARTIFACT_PROFILE && offer.version === ARTIFACT_CONTRACT_VERSION));
  if (providers.length !== 1) refuse('transfer.exact_provider_required');
  const provider = providers[0]!;
  const selection = selectArtifactTransferProfile({...provider, status: 'available'});
  if (!selection.ok) refuse('transfer.profile_unavailable');
  return {
    profile: 'morphir/cli/artifact-connection', contractVersion: '0.1.0',
    provider: structuredClone(provider) as unknown as Json,
  };
}
