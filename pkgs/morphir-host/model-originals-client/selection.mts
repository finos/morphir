import {modelOriginalsOffer} from './session.ts';
import {refuse} from '../connection/node-session.mts';
import type {Manifest} from '../execution-client/manifest.mts';
import type {Json} from '../execution-client/contracts.mts';
/** A model connection pins the actual offer and source discovery, not authority. */
export function originalsConnectionDescriptor(manifest: Manifest): Json {
  const providers=manifest.providers.filter(provider=>{
    const offer=modelOriginalsOffer(provider.capabilities);
    if(offer==='ambiguous')refuse('originals.ambiguous_offer');
    return provider.status==='available'&&offer==='supported';
  });
  if(!providers.length)refuse('originals.profile_unavailable');
  const sources=manifest.initialSources.filter(source=>providers.some(provider=>provider.id===source.providerId));
  return {profile:'morphir/cli/model-connection',contractVersion:'0.1.0',providers:structuredClone(providers) as unknown as Json,sources:structuredClone(sources) as unknown as Json};
}
