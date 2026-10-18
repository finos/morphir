import { fileURLToPath } from 'node:url';
/**
 * Static case authoring from the approved contract, never a compatibility runner.
 * No production/adapter imports, executions, outputs or observed-to-expected path.
 */
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const own = resolve(process.argv[2] ?? dirname(fileURLToPath(import.meta.url)));
const parent = resolve(own, '../../..');
const foundation = resolve(dirname(fileURLToPath(import.meta.url)), 'foundation/byte-recipes.json');
const catalog = JSON.parse(await readFile(foundation, 'utf8'));
const sha = (bytes: Uint8Array | string) => createHash('sha256').update(bytes).digest('hex');
const copy = <T>(value: T): T => structuredClone(value);
const measure = (bytes: Uint8Array) => ({ byteLength: bytes.length, sha256: sha(bytes) });
const textMeasure = (text: string) => ({ utf16Length: text.length, utf8: measure(Buffer.from(text, 'utf8')) });
const NONE = { kind: 'none' };
const EMPTY_HASH = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const INVALID_PREVIEW = 'Text preview unavailable: this file contains invalid UTF-8. Download preserves the original bytes.';
const STALE = 'These generated files are no longer available. Recompile to download them.';
const SELECTION = 'The download selection differs from the verified file inventory.';
const REFERENCE = 'A generated file reference is stale, duplicated or belongs to another output.';
const PATH = 'A generated file reference differs from its verified path.';
const PROFILE = 'morphir/workbench/artifacts';
const VERSION = '0.1.0-draft.1';
type Recipe = { kind: 'hex'; hex: string } | { kind: 'repeat-u8'; length: number; byte: number }
  | { kind: 'cycle-u8'; length: number } | { kind: 'chunk-indexed-u8'; length: number; seed: number };
type FileSpec = { path: string; kind: 'binary' | 'utf8-text'; content: Recipe; immutableId?: string };
type File = FileSpec & { bytes: Buffer; measured: any; preview: any };

function construct(recipe: Recipe): Buffer {
  if (recipe.kind === 'hex') return Buffer.from(recipe.hex, 'hex');
  if (recipe.kind === 'repeat-u8') return Buffer.alloc(recipe.length, recipe.byte);
  const bytes = Buffer.alloc(recipe.length);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = recipe.kind === 'cycle-u8' ? i % 256 : (i % 256) ^ ((Math.floor(i / 65536) + recipe.seed) % 256);
  }
  return bytes;
}

function fixed(id: string, path: string, kind: 'binary' | 'utf8-text' = 'binary'): FileSpec {
  const entry = catalog.recipes.find((item: any) => item.id === id);
  if (!entry) throw new Error('Missing independent recipe ' + id);
  const source = entry.recipe;
  const content: Recipe = source.kind === 'hex' ? { kind: 'hex', hex: source.hex }
    : source.kind === 'cycle-u8' ? { kind: 'cycle-u8', length: source.length }
    : { kind: 'chunk-indexed-u8', length: source.length, seed: source.seed };
  return { path, kind, content, immutableId: id };
}

function prefix(text: string, limit: number): string {
  let result = text.slice(0, limit);
  const final = result.charCodeAt(result.length - 1);
  if (final >= 0xd800 && final <= 0xdbff) result = result.slice(0, -1);
  return result;
}

function file(spec: FileSpec): File {
  const bytes = construct(spec.content);
  const measured = measure(bytes);
  if (spec.immutableId) {
    const entry = catalog.recipes.find((item: any) => item.id === spec.immutableId);
    if (entry.sha256 !== measured.sha256 || entry.byteLength !== measured.byteLength) throw new Error('Immutable recipe disagreement');
  }
  let preview: any;
  if (spec.kind === 'binary') preview = { kind: 'binary', prefix: measure(bytes.subarray(0, 65536)) };
  else {
    try {
      const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
      preview = { kind: text.length <= 65536 ? 'text' : 'text-prefix', text: textMeasure(prefix(text, 65536)) };
    } catch { preview = { kind: 'invalid-utf8' }; }
  }
  return { ...spec, bytes, measured, preview };
}

function definition(id: string, files: File[], input?: any) {
  return {
    id,
    offer: { id: 'provider-client', status: 'available', capabilities: [{ name: PROFILE, version: VERSION }] },
    input: input ?? { sessionId: 'session-client', target: 'fixture', irVersion: '4', ir: { formatVersion: 4 }, options: {} },
    context: { sourceId: 'client-source', revision: id === 'A' ? 1 : 2, epoch: id === 'A' ? 1 : 2 },
    peer: { kind: 'ready', generationId: 'generation-' + id, producer: { id: 'artifact-fixture', version: '0.1.0' },
      artifacts: files.map((item, index) => ({ id: 'artifact-' + id + '-' + index, path: item.path, kind: item.kind, content: item.content })),
      diagnostics: [] },
    localFaults: [],
  };
}

// Each transition below is authored, not derived by executing a client.
// The fixed scope reads every file in order, hashes every file in order, then releases once.
class AuthoredCase {
  definitions: any[];
  files: Record<string, File[]>;
  actions: any[] = [];
  events: any[] = [];
  checkpoints: any[] = [];
  states: Record<string, any> = {};
  results: Record<string, any> = {};
  current: any = null;
  registry: any = { kind: 'empty' };
  views: Record<string, string> = {};
  nextEffect: Record<string, number> = {};
  nextWire: Record<string, number> = {};
  readWork = 0;
  observationWork = 0;
  rawWork = 0;
  constructor(id: string, files: Record<string, File[]>, inputs: Record<string, any> = {}) {
    this.id = id;
    this.files = files;
    this.definitions = Object.entries(files).map(([attempt, items]) => definition(attempt, items, inputs[attempt]));
    for (const item of this.definitions) {
      this.states[item.id] = { id: item.id, phase: 'not-started', pending: [], signalAborted: null, terminal: { kind: 'pending' }, closeCalls: 0 };
      this.nextEffect[item.id] = 0; this.nextWire[item.id] = 1;
    }
  }
  id: string;
  bytes(id: string): number { return this.files[id].reduce((sum, item) => sum + item.bytes.length, 0); }
  allBytes(): number { return Object.keys(this.files).reduce((sum, id) => sum + this.bytes(id), 0); }
  act(action: any, transition: () => void = () => {}, result: any = NONE) {
    this.actions.push(copy(action)); transition();
    this.checkpoints.push({ actionIndex: this.actions.length - 1, eventCount: this.events.length, label: action.action === 'observe' ? action.label : null,
      currentContext: copy(this.current), attempts: this.definitions.map(item => copy(this.states[item.id])), registry: copy(this.registry), actionResult: copy(result) });
  }
  context(id: string) { this.act({ action: 'set-current', context: this.definitions.find(item => item.id === id).context }, () => { this.current = this.definitions.find(item => item.id === id).context; }); }
  effect(id: string, kind: string, argument: any) {
    const index = this.nextEffect[id]++;
    this.events.push({ kind: 'effect', attempt: id, index, effect: kind, argument });
    this.states[id].pending = [{ index, effect: kind }];
    return index;
  }
  settled(id: string) {
    const pending = this.states[id].pending[0];
    this.events.push({ kind: 'settled', attempt: id, index: pending.index, settlement: 'resolved' });
    this.states[id].pending = [];
  }
  wire(id: string, method: string, params: any) {
    return { frame: { kind: 'text', source: JSON.stringify({ jsonrpc: '2.0', id: this.nextWire[id]++, method, params }) } };
  }
  deliver(id: string, kind: string, transition: () => void, value: any = { kind: 'peer' }) {
    const index = this.states[id].pending[0].index;
    this.act({ action: 'deliver', effect: { attempt: id, index, kind }, value }, () => { this.settled(id); transition(); });
  }
  begin(id: string, extras: any[] = []) {
    const d = this.definitions.find(item => item.id === id);
    this.context(id);
    this.act({ action: 'start', attempt: id }, () => {
      this.readWork += this.bytes(id); this.observationWork += this.bytes(id);
      this.states[id].phase = 'connecting'; this.states[id].signalAborted = false;
      this.effect(id, 'connect', { signalAborted: false });
    });
    for (const action of extras) this.act({ ...action, attempt: id });
    this.deliver(id, 'connect', () => {
      this.states[id].phase = 'initializing';
      this.effect(id, 'initialize', this.wire(id, 'morphir.session.initialize', { protocolVersion: 1, sessionId: d.input.sessionId }));
    }, { kind: 'connect' });
    this.deliver(id, 'initialize', () => {
      this.states[id].phase = 'generating';
      this.effect(id, 'generate', this.wire(id, 'morphir.artifacts.generate', { contractVersion: VERSION, providerId: d.offer.id,
        generation: { ir: d.input.ir, irVersion: d.input.irVersion, target: d.input.target, options: d.input.options } }));
    });
    const reads = this.files[id].flatMap((item, index) => Array.from({ length: Math.max(1, Math.ceil(item.bytes.length / 65536)) },
      (_, part) => ({ file: index, offset: part * 65536, length: Math.min(65536, item.bytes.length - part * 65536) })));
    // Conservative canonical-peer raw-response expansion, not observed bytes:
    // full manifest budget, small initialization/release wrappers, and 1KiB
    // metadata allowance per exact independently specified base64 chunk.
    this.rawWork += 131072 + 4096 + 256 + reads.reduce((sum, read) => sum + 4 * Math.ceil(read.length / 3) + 1024, 0);
    const requestRead = (read: any) => this.effect(id, 'read', this.wire(id, 'morphir.artifacts.read', {
      contractVersion: VERSION, generationId: d.peer.generationId, artifactId: d.peer.artifacts[read.file].id, offset: read.offset, maxBytes: 65536 }));
    this.deliver(id, 'generate', () => { this.states[id].phase = 'receiving'; requestRead(reads[0]); });
    this.act({ action: 'drain-reads', attempt: id, maxReads: reads.length }, () => {
      this.readWork += reads.length * 65536;
      for (let i = 0; i < reads.length; i++) {
        this.settled(id);
        if (i + 1 < reads.length) requestRead(reads[i + 1]);
      }
      this.states[id].phase = 'verifying';
      this.effect(id, 'digest', this.files[id][0].measured);
    });
    for (let index = 0; index < this.files[id].length; index++) {
      this.deliver(id, 'digest', () => {
        if (index + 1 < this.files[id].length) this.effect(id, 'digest', this.files[id][index + 1].measured);
        else {
          this.states[id].phase = 'releasing';
          this.effect(id, 'release', this.wire(id, 'morphir.artifacts.release', { contractVersion: VERSION, generationId: d.peer.generationId }));
        }
      }, { kind: 'digest', result: 'actual' });
    }
    const cleanup = { kind: 'released', generationId: d.peer.generationId };
    this.deliver(id, 'release', () => {
      this.events.push({ kind: 'close', attempt: id });
      Object.assign(this.states[id], { phase: 'finished', closeCalls: 1, terminal: { kind: 'verified', cleanup } });
      this.results[id] = { kind: 'verified', manifest: { profile: PROFILE, contractVersion: VERSION, sessionId: d.input.sessionId,
        providerId: d.offer.id, generationId: d.peer.generationId, producer: d.peer.producer, target: d.input.target, irVersion: d.input.irVersion, diagnostics: [] },
        inventory: this.files[id].map((item, index) => ({ id: 'file-' + index, path: item.path, declaredKind: item.kind, bytes: item.measured, preview: item.preview })), cleanup };
    });
  }
  viewEvidence(id: string, views: string) {
    const limit = Math.min(65536, Math.floor(1048576 / this.files[id].length));
    return this.files[id].map((item, index) => {
      let content = ''; let state = item.preview.kind;
      if (state === 'text' || state === 'text-prefix') {
        const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(item.bytes);
        const owner = prefix(text, 65536); content = prefix(owner, limit);
        if (state === 'text-prefix' || content.length < owner.length) state = 'text-prefix';
      } else if (state === 'invalid-utf8') content = INVALID_PREVIEW;
      return { file: 'file-' + index, path: item.path, binary: item.kind === 'binary', encoding: 'verified-bytes', byteLength: item.bytes.length,
        previewState: state, content: textMeasure(content), binaryPreview: item.kind === 'binary' ? measure(item.bytes.subarray(0, limit)) : null,
        reference: { views, file: 'file-' + index } };
    });
  }
  publish(id: string, views: string) {
    this.observationWork += this.bytes(id);
    this.act({ action: 'publish', attempt: id, views }, () => { this.views[views] = id; this.registry = { kind: 'published', views }; },
      { kind: 'published', views, artifacts: this.viewEvidence(id, views) });
  }
  select(views: string, indices: number[], mutations: any[] = []) { return { views, indices, mutations }; }
  download(views: any, complete: boolean, refusal?: string) {
    this.observationWork += this.allBytes();
    const files = views.indices.map((index: number) => this.files[this.views[views.views]][index]).map((item: File) => ({ path: item.path, bytes: item.measured }));
    this.act({ action: 'download', views, complete }, () => {}, refusal ? { kind: 'refused', operation: 'download', message: refusal } : { kind: 'download', files });
  }
  archive(views: any, refusal?: string) {
    this.observationWork += 3 * this.allBytes();
    const entries = views.indices.map((index: number) => this.files[this.views[views.views]][index]).map((item: File) => ({ path: item.path, bytes: item.measured }));
    const encodedByteLength = 22 + entries.reduce((sum: number, item: any) => sum + 76 + 2 * Buffer.byteLength(item.path) + item.bytes.byteLength, 0);
    this.act({ action: 'archive', views }, () => {}, refusal ? { kind: 'refused', operation: 'archive', message: refusal }
      : { kind: 'archive', archive: { encodedByteLength, entries } });
  }
  mutate(id: string, index: number) {
    this.observationWork += this.bytes(id);
    this.act({ action: 'mutate-copy', attempt: id, file: 'file-' + index, offset: 0, xor: 255 });
  }
  finish() {
    const attempts = this.definitions.map(d => ({
      id: d.id, capture: this.states[d.id].phase === 'construction-refused' ? null : { profile: PROFILE, contractVersion: VERSION, providerId: d.offer.id, sessionId: d.input.sessionId, target: d.input.target, irVersion: d.input.irVersion },
      phase: this.states[d.id].phase, result: this.results[d.id], closeCalls: this.states[d.id].closeCalls,
      effects: Object.fromEntries(['connect', 'initialize', 'generate', 'read', 'digest', 'release'].map(kind => [kind,
        this.events.filter(event => event.kind === 'effect' && event.attempt === d.id && event.effect === kind).length])),
    }));
    return { id: this.id, operation: 'artifact-client', format: 'json',
      input: { attempts: this.definitions, actions: this.actions }, expected: { status: 'ok', value: { events: this.events, checkpoints: this.checkpoints, attempts } } };
  }
}

// The pure authoring utilities above are copied from independent author source
// 79a6a62f990d6de80852040ede431446d3956f1f78e0184f37805f025412da10.
// The following transition expectations are separately authored from the approved
// profile/controller ownership contract. No implementation is imported or run.
function compressed(source: string): any {
  const runs = [...source.matchAll(/([\x00-\x7f])\1{63,}/g)];
  if (!runs.length) return {kind:'text',source};
  const segments:any[]=[];let at=0;
  for(const run of runs){if(run.index!>at)segments.push({kind:'literal',source:source.slice(at,run.index)});segments.push({kind:'repeat-ascii',byte:run[0].charCodeAt(0),count:run[0].length});at=run.index!+run[0].length;}
  if(at<source.length)segments.push({kind:'literal',source:source.slice(at)});
  return {kind:'segments',segments};
}
class Trace extends AuthoredCase {
  wire(id:string,method:string,params:any){return {frame:compressed(JSON.stringify({jsonrpc:'2.0',id:this.nextWire[id]++,method,params}))};}
  d(id='A'){return this.definitions.find(item=>item.id===id);}
  effect(id:string,kind:string,argument:any){const index=this.nextEffect[id]++;this.events.push({kind:'effect',attempt:id,index,effect:kind,argument});this.states[id].pending.push({index,effect:kind});return index;}
  settle(id:string,index:number,rejected=false){const state=this.states[id];const at=state.pending.findIndex((p:any)=>p.index===index);if(at<0)throw Error('author nonexistent pending');state.pending.splice(at,1);this.events.push({kind:'settled',attempt:id,index,settlement:rejected?'rejected':'resolved'});}
  settled(id:string){this.settle(id,this.states[id].pending[0].index);}
  closed(id:string){this.events.push({kind:'close',attempt:id});this.states[id].closeCalls++;}
  done(id:string,result:any,close=true){if(close)this.closed(id);this.states[id].phase='finished';this.states[id].terminal={kind:result.kind,cleanup:result.cleanup};this.results[id]=result;}
  fail(id:string,failure:any,cleanup:any,close=true){this.done(id,{kind:'failed',failure,cleanup},close);}
  startOnly(id='A'){this.act({action:'start',attempt:id},()=>{this.readWork+=this.bytes(id);this.observationWork+=this.bytes(id);Object.assign(this.states[id],{phase:'connecting',signalAborted:false});this.effect(id,'connect',{signalAborted:false});});}
  open(id='A'){
    const d=this.d(id);this.context(id);this.startOnly(id);
    this.deliver(id,'connect',()=>{this.states[id].phase='initializing';this.effect(id,'initialize',this.wire(id,'morphir.session.initialize',{protocolVersion:1,sessionId:d.input.sessionId}));},{kind:'connect'});
    this.deliver(id,'initialize',()=>{this.states[id].phase='generating';const input=copy(d.input);for(const v of d.localValues??[]){let slot=input[v.field];let parent=input,key=v.field;for(const s of v.path){parent=slot;key=s.kind==='member'?s.key:s.index;slot=parent[key];}parent[key]=String.fromCharCode(v.byte).repeat(v.count);}this.effect(id,'generate',this.wire(id,'morphir.artifacts.generate',{contractVersion:VERSION,providerId:d.offer.id,generation:{ir:input.ir,irVersion:input.irVersion,target:input.target,options:input.options}}));});
  }
  readRequest(id='A',fileIndex=0,offset=0){const d=this.d(id);this.effect(id,'read',this.wire(id,'morphir.artifacts.read',{contractVersion:VERSION,generationId:d.peer.generationId,artifactId:d.peer.artifacts[fileIndex].id,offset,maxBytes:65536}));}
  releaseRequest(id='A'){const d=this.d(id);this.states[id].phase='releasing';this.effect(id,'release',this.wire(id,'morphir.artifacts.release',{contractVersion:VERSION,generationId:d.peer.generationId}));}
  receive(id='A'){this.deliver(id,'generate',()=>{this.states[id].phase='receiving';this.readRequest(id);});}
  hashPending(id='A'){this.receive(id);this.act({action:'drain-reads',attempt:id,maxReads:1},()=>{this.readWork+=65536;this.settled(id);this.states[id].phase='verifying';this.effect(id,'digest',this.files[id][0].measured);});}
  rejectEffect(id:string,kind:string,next:()=>void){const index=this.states[id].pending.find((p:any)=>p.effect===kind).index;this.act({action:'reject',effect:{attempt:id,index,kind},message:'authored transport rejection'},()=>{this.settle(id,index,true);next();});}
  raw(id:string,kind:string,source:string,next:()=>void){this.rawWork+=Buffer.byteLength(source);this.deliver(id,kind,next,{kind:'raw',frame:compressed(source)});}
  released(id='A',next?:()=>void){this.deliver(id,'release',()=>{this.closed(id);if(next)next();});}
  resultFailedAfterRelease(id:string,failure:any){this.released(id,()=>this.fail(id,failure,{kind:'released',generationId:this.d(id).peer.generationId},false));}
}
const unpublished:any[]=[];const coverageOwn:any[]=[];
function add(c:Trace,family:string,requirement:string){const value=c.finish();const raw=JSON.stringify(value);if(Buffer.byteLength(JSON.stringify(value.input))>1048576||Buffer.byteLength(JSON.stringify(value.expected.value))>1048576)throw Error('author source/evidence bound '+c.id);unpublished.push(value);coverageOwn.push({id:c.id,family,requirement,adapterExecuted:false});}
const one=(id:string)=>new Trace(id,{A:[file({path:'owned.bin',kind:'binary',content:{kind:'hex',hex:'0102ff'}})]});
const unknown={kind:'connection-closed',generationId:null,reason:'unknown-retention'};
const invalid=(code:string)=>({kind:'protocol',failure:{kind:'invalid',code:'artifacts.'+code}});
const generic={kind:'other',message:'Authored UI explanation; compatibility compares the error category.'};
function manifest(c:Trace){const d=c.d();return {jsonrpc:'2.0',id:2,result:{profile:PROFILE,contractVersion:VERSION,status:'ready',sessionId:d.input.sessionId,providerId:d.offer.id,generationId:d.peer.generationId,producer:d.peer.producer,target:d.input.target,irVersion:d.input.irVersion,artifacts:c.files.A.map((f,i)=>({id:d.peer.artifacts[i].id,path:f.path,kind:f.kind,byteLength:f.bytes.length,sha256:f.measured.sha256})),diagnostics:[]}};}

// Capability/profile selection is a construction boundary, before connection.
for(const [name,change] of [
 ['missing-profile',(d:any)=>d.offer.capabilities=[]],
 ['wrong-exact-draft',(d:any)=>d.offer.capabilities[0].version='0.1.0-draft.2'],
 ['disconnected',(d:any)=>d.offer.status='disconnected'],
] as const){const c=one('client-selection-'+name);change(c.d());c.context('A');c.act({action:'start',attempt:'A'},()=>{Object.assign(c.states.A,{phase:'construction-refused',terminal:{kind:'construction-refused'}});c.results.A={kind:'construction-refused',failure:invalid('unavailable')};});add(c,'selection','Unavailable exact profile refuses construction with zero external effects.');}

// Generation request size includes the complete JSON-RPC envelope. Compact
// local values are authored before construction; measured outbound frames remain
// lossless through explicit repeat segments, not an expected-frame digest.
for(const over of [0,1]){
 const c=new Trace('client-request-one-mib-'+(over?'oneover':'exact'),{A:[]});const d=c.d();d.input.options={padding:''};
 const skeleton=JSON.stringify({jsonrpc:'2.0',id:2,method:'morphir.artifacts.generate',params:{contractVersion:VERSION,providerId:d.offer.id,generation:{ir:d.input.ir,irVersion:d.input.irVersion,target:d.input.target,options:d.input.options}}});
 d.localValues=[{kind:'repeat-ascii-value',field:'options',path:[{kind:'member',key:'padding'}],byte:97,count:1048576-Buffer.byteLength(skeleton)+over}];
 if(over){c.context('A');c.act({action:'start',attempt:'A'},()=>{Object.assign(c.states.A,{phase:'construction-refused',terminal:{kind:'construction-refused'}});c.results.A={kind:'construction-refused',failure:{kind:'input',reason:'request-limit'}};});}
 else{c.open();c.deliver('A','generate',()=>c.releaseRequest());c.released('A',()=>c.done('A',{kind:'verified',manifest:{...manifest(c).result,status:undefined,artifacts:undefined},inventory:[],cleanup:{kind:'released',generationId:d.peer.generationId}},false));delete c.results.A.manifest.status;delete c.results.A.manifest.artifacts;}
 add(c,'request-budget','Exactly1MiB complete request is allowed and oneover refuses before connecting.');
}
{
 const c=one('client-request-control-escaping-oneover');c.d().input.options={padding:''};c.d().localValues=[{kind:'repeat-ascii-value',field:'options',path:[{kind:'member',key:'padding'}],byte:0,count:174763}];c.context('A');c.act({action:'start',attempt:'A'},()=>{Object.assign(c.states.A,{phase:'construction-refused',terminal:{kind:'construction-refused'}});c.results.A={kind:'construction-refused',failure:{kind:'input',reason:'request-limit'}};});add(c,'request-budget','JSON escape expansion counts toward the complete request before any connection.');
}

// Held/rejected await boundaries. Failure owns only this attempt socket.
for(const stage of ['connect','initialize','generate','read','digest','release']){
 const c=one('client-rejected-'+stage);
 if(stage==='initialize'){c.context('A');c.startOnly();c.deliver('A','connect',()=>{c.states.A.phase='initializing';c.effect('A','initialize',c.wire('A','morphir.session.initialize',{protocolVersion:1,sessionId:c.d().input.sessionId}));},{kind:'connect'});c.rejectEffect('A',stage,()=>c.fail('A',generic,unknown));}
 else if(stage==='connect'){c.context('A');c.startOnly();c.rejectEffect('A',stage,()=>c.fail('A',generic,{kind:'not-connected'},false));}
 else{
   c.open();
   if(stage==='initialize')throw Error('initialize authored separately below');
   if(stage==='read')c.receive();
   if(stage==='digest'||stage==='release')c.hashPending();
   if(stage==='release')c.deliver('A','digest',()=>c.releaseRequest(),{kind:'digest',result:'actual'});
   c.rejectEffect('A',stage,()=>{
     if(stage==='generate')c.fail('A',generic,unknown);
     else if(stage==='release')c.fail('A',generic,{kind:'connection-closed',generationId:c.d().peer.generationId,reason:'release-failed'});
     else c.releaseRequest();
   });
   if(stage==='read'||stage==='digest')c.resultFailedAfterRelease('A',stage==='digest'?{kind:'verification',reason:'digest-unavailable'}:generic);
 }
 add(c,'await-rejection','Rejected '+stage+' settles once, exposes no owner and cleans only captured resources.');
}
const manifestMutations:[string,string,(m:any)=>void][]=[
 ['session','invalid_identity',m=>m.result.sessionId='other-session'],
 ['provider','invalid_identity',m=>m.result.providerId='other-provider'],
 ['target','invalid_identity',m=>m.result.target='other-target'],
 ['ir-version','invalid_identity',m=>m.result.irVersion='3'],
 ['profile','unavailable',m=>m.result.profile='other/profile'],
 ['version','unavailable',m=>m.result.contractVersion='0.1.0-draft.2'],
 ['producer-core','invalid_request',m=>m.result.producer.version='9007199254740992.0.0'],
 ['producer-identity','invalid_identity',m=>m.result.producer.id=''],
 ['traversal-path','invalid_path',m=>m.result.artifacts[0].path='../escape.bin'],
 ['control-path','invalid_path',m=>m.result.artifacts[0].path='bad\u0085.bin'],
 ['portable-collision','invalid_path_set',m=>m.result.artifacts.push({...m.result.artifacts[0],id:'second',path:'OWNED.bin'})],
 ['duplicate-handle','invalid_identity',m=>m.result.artifacts.push({...m.result.artifacts[0],path:'second.bin'})],
 ['bad-digest','invalid_content',m=>m.result.artifacts[0].sha256='A'.repeat(64)],
 ['oneover-file','file_size',m=>m.result.artifacts[0].byteLength=16777217],
 ['extra-field','invalid_request',m=>m.result.unexpected=true],
];
for(const [name,code,mutate] of manifestMutations){const c=one('client-manifest-'+name);c.open();const m=manifest(c);mutate(m);c.raw('A','generate',JSON.stringify(m),()=>c.fail('A',invalid(code),unknown));add(c,'hostile-manifest','Raw manifest '+name+' cannot become retained or downloadable.');}
for(const [name,code,transform] of [
 ['duplicate-member','invalid_request',(s:string)=>s.replace('"status":"ready"','"status":"ready","status":"ready"')],
 ['fractional-file','file_size',(s:string)=>s.replace('"byteLength":3','"byteLength":3.1')],
 ['underflow-file','file_size',(s:string)=>s.replace('"byteLength":3','"byteLength":1e-999')],
 ['noncanonical-id','invalid_identity',(s:string)=>s.replace('"id":2','"id":2.0')],
 ['illformed-unicode','invalid_request',(s:string)=>s.replace('"diagnostics":[]','"diagnostics":[{"severity":"info","code":null,"message":"\\ud800","location":null}]')],
] as const){const c=one('client-manifest-'+name);c.open();c.raw('A','generate',transform(JSON.stringify(manifest(c))),()=>c.fail('A',invalid(code),unknown));add(c,'literal-wire','Raw literal '+name+' is refused before lossy parsing can erase evidence.');}
{
 const c=one('client-manifest-oneover-reply');c.open();c.raw('A','generate',' '.repeat(131073),()=>c.fail('A',invalid('reply_limit'),unknown));add(c,'reply-budget','Oneover128KiB complete raw reply is refused before parsing.');
}
{
 const c=one('client-remote-error-exact-code-message');c.open();const remote={jsonrpc:'2.0',id:2,error:{code:-32000,message:'Independent remote failure.',data:{profile:PROFILE,contractVersion:VERSION,code:'artifacts.capacity'}}};c.raw('A','generate',JSON.stringify(remote),()=>c.fail('A',{kind:'protocol',failure:{kind:'remote',code:'artifacts.capacity',rpcCode:-32000,message:'Independent remote failure.'}},unknown));add(c,'remote-error','Remote signed i32 code and wire message survive typed failure without generic normalization.');
}
function readReply(c:Trace){return {jsonrpc:'2.0',id:3,result:{profile:PROFILE,contractVersion:VERSION,generationId:c.d().peer.generationId,artifactId:c.d().peer.artifacts[0].id,offset:0,nextOffset:3,content:'AQL/'}};}
const readMutations:[string,string,(m:any)=>void][]=[
 ['generation','invalid_identity',m=>m.result.generationId='other-generation'],
 ['artifact','invalid_identity',m=>m.result.artifactId='other-artifact'],
 ['offset','invalid_range',m=>m.result.offset=1],
 ['progress','invalid_range',m=>m.result.nextOffset=2],
 ['base64','invalid_content',m=>m.result.content='AQL_'],
 ['noncanonical-base64','invalid_content',m=>m.result.content='AQ==\n'],
 ['empty-progress','invalid_range',m=>{m.result.content='';m.result.nextOffset=0;}],
 ['extra-field','invalid_request',m=>m.result.unexpected=true],
];
for(const [name,code,mutate] of readMutations){const c=one('client-read-'+name);c.open();c.receive();const m=readReply(c);mutate(m);c.raw('A','read',JSON.stringify(m),()=>c.releaseRequest());c.resultFailedAfterRelease('A',invalid(code));add(c,'hostile-chunk','Malformed chunk '+name+' releases exact retained generation without hashing or exposing bytes.');}
for(const [name,code,change] of [
 ['fractional-offset','invalid_range',(s:string)=>s.replace('"offset":0','"offset":0.5')],
 ['underflow-offset','invalid_range',(s:string)=>s.replace('"offset":0','"offset":1e-999')],
 ['duplicate-offset','invalid_request',(s:string)=>s.replace('"offset":0','"offset":0,"offset":0')],
] as const){const c=one('client-read-'+name);c.open();c.receive();c.raw('A','read',change(JSON.stringify(readReply(c))),()=>c.releaseRequest());c.resultFailedAfterRelease('A',invalid(code));add(c,'literal-wire','Chunk literal '+name+' preserves refusal evidence before rounding or duplicate erasure.');}
for(const result of ['wrong-32','short-31'] as const){const c=one('client-digest-'+result);c.open();c.hashPending();c.deliver('A','digest',()=>c.releaseRequest(),{kind:'digest',result});c.resultFailedAfterRelease('A',{kind:'verification',reason:'digest'});add(c,'verification','A '+result+' digest cannot create a verified owner; captured generation is released once.');}
{
 const c=one('client-digest-mutated-input');c.open();c.hashPending();c.deliver('A','digest',()=>c.releaseRequest(),{kind:'digest-mutated-input',xor:255});c.resultFailedAfterRelease('A',{kind:'verification',reason:'digest'});add(c,'verification','Digest effect mutating its argument cannot establish byte integrity or expose output.');
}
{
 const c=one('client-generation-failed-diagnostics');const diagnostics=[{severity:'error',code:'fixture.failure',message:'Independent generator diagnostic.',location:null}];c.d().peer={kind:'failed',diagnostics};c.open();c.deliver('A','generate',()=>c.done('A',{kind:'generation-failed',diagnostics,cleanup:{kind:'not-retained'}}));add(c,'generation-failure','Typed generator failure retains diagnostics and closes without reads, hashes or release.');
}

// Stale context is checked after every asynchronous boundary. A valid obsolete
// manifest is learned only to release its exact generation, never to publish.
for(const stage of ['connect','initialize','generate','read','digest','release']){
 const c=one('client-stale-after-'+stage);
 if(stage==='connect'){c.context('A');c.startOnly();}
 else if(stage==='initialize'){c.context('A');c.startOnly();c.deliver('A','connect',()=>{c.states.A.phase='initializing';c.effect('A','initialize',c.wire('A','morphir.session.initialize',{protocolVersion:1,sessionId:c.d().input.sessionId}));},{kind:'connect'});}
 else{c.open();if(stage==='read')c.receive();if(stage==='digest'||stage==='release')c.hashPending();if(stage==='release')c.deliver('A','digest',()=>c.releaseRequest(),{kind:'digest',result:'actual'});}
 c.act({action:'set-current',context:null},()=>{c.current=null;});
 if(stage==='connect'||stage==='initialize')c.deliver('A',stage,()=>c.done('A',{kind:'discarded',cleanup:unknown}),stage==='connect'?{kind:'connect'}:{kind:'peer'});
 else if(stage==='release')c.released('A',()=>c.done('A',{kind:'discarded',cleanup:{kind:'released',generationId:c.d().peer.generationId}},false));
 else{c.deliver('A',stage,()=>c.releaseRequest(),stage==='digest'?{kind:'digest',result:'actual'}:{kind:'peer'});c.released('A',()=>c.done('A',{kind:'discarded',cleanup:{kind:'released',generationId:c.d().peer.generationId}},false));}
 add(c,'stale-boundary','After held '+stage+' settles, obsolete attempt cleans its captured resource and exposes no owner.');
}
// Cancellation during a pending wire exchange must close immediately, preserve
// the exact known-or-unknown generation and never wait to start cleanup.
for(const stage of ['initialize','generate','read']){
 const c=one('client-cancel-pending-'+stage);
 if(stage==='initialize'){c.context('A');c.startOnly();c.deliver('A','connect',()=>{c.states.A.phase='initializing';c.effect('A','initialize',c.wire('A','morphir.session.initialize',{protocolVersion:1,sessionId:c.d().input.sessionId}));},{kind:'connect'});}
 else{c.open();if(stage==='read')c.receive();}
 const cleanup={kind:'connection-closed',generationId:stage==='read'?c.d().peer.generationId:null,reason:'pending-exchange'};
 c.act({action:'cancel',attempt:'A'},()=>{c.states.A.signalAborted=true;c.closed('A');c.events.push({kind:'cancel-result',attempt:'A',cleanup});});
 c.deliver('A',stage,()=>c.done('A',{kind:'discarded',cleanup},false));
 add(c,'cancel-boundary','Cancel pending '+stage+' immediately closes its own socket; late reply cannot resurrect an owner.');
}
{
 const c=one('client-cancel-pending-connect-late-success');c.context('A');c.startOnly();c.act({action:'cancel',attempt:'A'},()=>{c.states.A.signalAborted=true;c.events.push({kind:'cancel-result',attempt:'A',cleanup:{kind:'not-connected'}});});c.deliver('A','connect',()=>c.done('A',{kind:'discarded',cleanup:unknown}),{kind:'connect'});add(c,'cancel-boundary','Late connect after cancellation is closed by its attempt without initialization or generation.');
}
{
 const c=one('client-cancel-pending-digest-release-once');c.open();c.hashPending();const hash=c.states.A.pending[0].index;const cleanup={kind:'released',generationId:c.d().peer.generationId};
 c.act({action:'cancel',attempt:'A'},()=>{c.states.A.signalAborted=true;c.releaseRequest();});const release=c.states.A.pending.find((p:any)=>p.effect==='release').index;
 c.act({action:'deliver',effect:{attempt:'A',index:release,kind:'release'},value:{kind:'peer'}},()=>{c.settle('A',release);c.closed('A');c.events.push({kind:'cancel-result',attempt:'A',cleanup});});
 c.act({action:'deliver',effect:{attempt:'A',index:hash,kind:'digest'},value:{kind:'digest',result:'actual'}},()=>{c.settle('A',hash);c.done('A',{kind:'discarded',cleanup},false);});add(c,'cancel-boundary','Cancellation releases while hash is held, memoizes cleanup, then discards late verified result.');
}

// A late old attempt must never clear, release or close a newer attempt's owner.
for(const stage of ['generate','digest']){
 const c=new Trace('client-old-'+stage+'-cannot-clear-new-owner',{A:[file({path:'old.bin',kind:'binary',content:{kind:'hex',hex:'01'}})],B:[file({path:'new.bin',kind:'binary',content:{kind:'hex',hex:'0203'}})]});
 c.open('A');if(stage==='digest')c.hashPending('A');
 c.begin('B');c.publish('B','views-B');
 c.deliver('A',stage,()=>c.releaseRequest('A'),stage==='digest'?{kind:'digest',result:'actual'}:{kind:'peer'});
 c.released('A',()=>c.done('A',{kind:'discarded',cleanup:{kind:'released',generationId:c.d('A').peer.generationId}},false));
 c.download(c.select('views-B',[0]),true);c.archive(c.select('views-B',[0]));
 add(c,'attempt-isolation','A delayed '+stage+' from old A releases only generation-A, preserving verified B and its downloadable bytes.');
}
{
 const c=one('client-channel-closed-during-hash');c.open();c.hashPending();c.act({action:'close-channel',attempt:'A'},()=>c.closed('A'));
 const cleanup={kind:'connection-closed',generationId:c.d().peer.generationId,reason:'unknown-retention'};
 c.deliver('A','digest',()=>c.fail('A',generic,cleanup),{kind:'digest',result:'actual'});
 add(c,'closed-channel','A closed owner socket prevents publication even after valid digest, with exact actual close-call accounting.');
}
{
 const c=one('client-release-malformed-acknowledgement');c.open();c.hashPending();c.deliver('A','digest',()=>c.releaseRequest(),{kind:'digest',result:'actual'});
 c.raw('A','release',JSON.stringify({jsonrpc:'2.0',id:4,result:{unexpected:true}}),()=>c.fail('A',generic,{kind:'connection-closed',generationId:c.d().peer.generationId,reason:'release-failed'}));
 add(c,'release-failure','Malformed release acknowledgement closes captured socket and suppresses the already verified byte owner.');
}

{
 const c=one('client-literal-private-marker-caller-objects');
 c.d().input.ir={formatVersion:4,nested:{$serde_json:'ordinary', '$serde_json::private::Number':'1'}};
 c.d().input.options={literal:{'$serde_json::private::RawValue':'{"x":1,"x":2}'},array:[{'$serde_json::private::Number':'1e-999'}]};
 c.begin('A');
 add(c,'literal-capture','Private-looking maps and duplicate-looking JSON strings remain exact ordinary IR/options through captured outbound requests.');
}
for(const [name,rawCode,accepted] of [['mathematical-code','-32000e0',true],['oneover-i32-code','2147483648',false]] as const){
 const c=one('client-remote-'+name);c.open();
 const source='{"jsonrpc":"2.0","id":2,"error":{"code":'+rawCode+',"message":"Literal remote message.","data":{"profile":"'+PROFILE+'","contractVersion":"'+VERSION+'","code":"artifacts.capacity"}}}';
 c.raw('A','generate',source,()=>c.fail('A',accepted?{kind:'protocol',failure:{kind:'remote',code:'artifacts.capacity',rpcCode:-32000,message:'Literal remote message.'}}:invalid('invalid_range'),unknown));
 add(c,'literal-wire','Signed remote codes retain exact mathematical i32 validation before Number conversion.');
}

await mkdir(resolve(own,'cases'),{recursive:true});
const frozen=[];
for(const value of unpublished){const body=JSON.stringify(value,null,2)+'\n';const path='cases/'+value.id+'.json';const location=resolve(own,path);const prior=await readFile(location,'utf8').catch(()=>null);if(prior!==null&&prior!==body)throw Error('Frozen case changed '+value.id);await writeFile(location,body);frozen.push({id:value.id,path,caseSha256:sha(body),inputSha256:sha(JSON.stringify(value.input)),expectedSha256:sha(JSON.stringify(value.expected))});}
await writeFile(resolve(own,'coverage.json'),JSON.stringify(coverageOwn,null,2)+'\n');
await writeFile(resolve(own,'manifest.json'),JSON.stringify({authoring:'Independently source-authored before any client adapter output is read or run.',cases:frozen},null,2)+'\n');
console.log(JSON.stringify({cases:frozen.length,manifestSha256:sha(await readFile(resolve(own,'manifest.json')))}));
