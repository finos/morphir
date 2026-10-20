import {test} from 'node:test';
import assert from 'node:assert/strict';
import {originalsConnectionDescriptor} from './selection.mts';
import type {Manifest} from '../execution-client/manifest.mts';
const originals={name:'morphir/workbench/model-originals',version:'0.1.0-draft.1'};
const workspace={name:'morphir/workspace/open',version:'1'};
function manifest(capabilities:Manifest['providers'][number]['capabilities']):Manifest {
 return {protocolVersion:1,sessionId:'session-A',webSocketPath:'/rpc',
  providers:[{id:'provider-A',status:'available',capabilities}],
  initialSources:[{providerId:'provider-A',locator:'workspace:orders',displayName:'Orders'}]};
}
test('model connection setup requires both exact capabilities before publishing sources',()=>{
 const value=originalsConnectionDescriptor(manifest([originals,workspace])) as Record<string,unknown>;
 assert.deepEqual(value.sources,manifest([]).initialSources);
});
for(const [name,capabilities] of [
 ['missing workspace',[originals]],
 ['unsupported workspace',[originals,{...workspace,version:'2'}]],
 ['duplicate workspace',[originals,workspace,workspace]],
 ['missing originals',[workspace]],
 ['unsupported originals',[{...originals,version:'0.2.0'},workspace]],
 ['duplicate originals',[originals,originals,workspace]],
] as const)test(name+' refuses model connection setup',()=>{
 assert.throws(()=>originalsConnectionDescriptor(manifest([...capabilities])),
  (error:unknown)=>error instanceof Error&&/^originals\.(profile_unavailable|ambiguous_offer)$/.test(error.message));
});
test('only providers supporting both capabilities contribute connection sources',()=>{
 const value=manifest([originals,workspace]);
 value.providers.push({id:'wrong-workspace',status:'available',capabilities:[originals,{...workspace,version:'2'}]},
  {id:'disconnected',status:'disconnected',capabilities:[originals,workspace]});
 value.initialSources.push({providerId:'wrong-workspace',locator:'workspace:wrong',displayName:'Wrong'},
  {providerId:'disconnected',locator:'workspace:gone',displayName:'Gone'});
 const selected=originalsConnectionDescriptor(value) as Record<string,unknown>;
 assert.deepEqual(selected.sources,[value.initialSources[0]]);
 assert.deepEqual((selected.providers as Manifest['providers']).map(provider=>provider.id),['provider-A']);
});
