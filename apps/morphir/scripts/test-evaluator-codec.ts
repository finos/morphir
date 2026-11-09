import type { ConformanceReport, VerificationReport } from '../../../tests/cli-contracts.ts';
// Mock transport responses exercise the host codec. They are never Rust parity.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const repo=fileURLToPath(new URL('../../../',import.meta.url)),home=process.env.MOON_HOME;
assert.ok(home,'Supply pinned MOON_HOME');
const root=mkdtempSync(join(tmpdir(),'morphir-evaluator-codec-'));
function run(program: string,args: string[],status=0) {
  const r=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:180000,maxBuffer:8388608});
  assert.equal(r.error,undefined);assert.equal(r.status,status,r.stderr+'\n'+r.stdout);return r;
}
const cli=join(repo,'_build/js/debug/build/finos/morphir/node/node.js');
const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
try {
  const fixture=JSON.parse(run(join(home,'bin/moon'),['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  run(join(home,'bin/moon'),['build','--target','js']);
  const model=join(root,'model.json'),cases=join(root,'cases.ion'),program=join(root,'fixture-binary'),helper=join(root,'fixture-worker.mjs'),pin=join(root,'pin.json'),cancelFile=join(root,'cancel');
  writeFileSync(model,fixture.rustConformanceIR);
  writeFileSync(cases,'{profile:"morphir-conformance-v1",version:"codec-test-v1",provenance:"Mock adapter test; direct literal 42",cases:[{id:"literal",entry:"rust-conformance:main#answer",arguments:[],expected:42}]}');
  const bytes='codec mock binary; not Rust';writeFileSync(program,bytes);
  writeFileSync(pin,JSON.stringify({profile:'morphir-rust-evaluator-pin-v1',protocol:'1.1.0-draft.1',sourceRevision:'1'.repeat(40),runtimeRevision:'2'.repeat(40),binaryIdentity:createHash('sha256').update(bytes).digest('hex')}));
  for(const [mutation,reason] of [
    ['',null],
    ['report.version="future"','rust_protocol'],
    ['report.results=[]',''],
    ['report.results.push(report.results[0])',''],
    ['report.results[0].id="other"','rust_call_identity'],
    ['report.results[0].entrypoint="other:main#answer"','rust_call_identity'],
    ['report.results[0].status="pending"','rust_status'],
    ['report.results[0].value.type=["Unit",{}]','rust_return_type'],
    ['report.results[0].value.value={kind:"string",value:"42"}',''],
    ['report.results[0].value.value={kind:"integer",value:"9223372036854775808"}','rust_integer_range'],
    ['report.results[0].value.value={kind:"integer",value:"43"}','mismatch'],
    ['report.results[0]={id:input.calls[0].id,entrypoint:input.calls[0].entrypoint,status:"error",code:"UNKNOWN_ERROR"}','rust_runtime_error'],
    ['response.requestIdentity="0".repeat(64)','rust_receipt_identity'],
    ['process.stderr.write("execution.tree_termination_failed\\n");process.exit(1)','tree_cleanup'],
    ['writeFileSync(request.cancelFile,"cancel")','cancelled'],
  ] as const) {
    rmSync(cancelFile,{force:true});
    writeFileSync(helper,`import {readFileSync,writeFileSync} from 'node:fs';import {createHash} from 'node:crypto';const hash=x=>createHash('sha256').update(x).digest('hex');
if(process.argv[2]==='--identity')process.stdout.write(JSON.stringify({binaryIdentity:hash(readFileSync(process.argv[3]))}));else {
const request=JSON.parse(readFileSync(process.argv[2],'utf8')),input=JSON.parse(request.input);
const report={version:'1.1.0-draft.1',provider:'morphir_ir',results:[{id:input.calls[0].id,entrypoint:input.calls[0].entrypoint,status:'value',value:{type:['Reference',{},[[['morphir'],['s','d','k']],[['basics']],['int']],[]],value:{kind:'integer',value:'42'}}}]};
const response={profile:'morphir-rust-evaluator-result-v1',requestIdentity:hash(request.input),binaryIdentity:request.binaryIdentity,helperIdentity:request.helperIdentity,report};${mutation};process.stdout.write(JSON.stringify(response));}`);
    const report: ConformanceReport=JSON.parse(run(process.execPath,[cli,'conform',model,'--cases',cases,'--execution-helper',join(repo,'apps/morphir/build-provider/execution.mjs'),'--home',home,...dependencies,'--rust-evaluator',program,'--rust-evaluator-pin',pin,'--rust-helper',helper,'--require-evaluator','rust',...(reason==='cancelled'?['--cancel-file',cancelFile]:[]),'--json'],reason===null?0:reason==='cancelled'?130:1).stdout);
    const rust=report.coverage.find(l=>l.provider==='rust')!.calls[0];
    assert.equal(report.successful,reason===null);
    assert.ok(report.coverage.filter(l=>l.provider!=='rust').every(l=>l.calls[0]!.status==='matched'),JSON.stringify(report));
    if(reason===null)assert.equal(rust!.status,'matched');else if(reason==='mismatch') {
      assert.equal(rust!.status,'mismatch');assert.equal(rust!.id,'literal');assert.equal(rust!.mismatchPath,'');
    } else if(reason==='cancelled') {
      assert.equal(report.cancelled,true);assert.equal(rust!.status,'cancelled');assert.equal(rust!.expected,null);
    } else {
      assert.equal(rust!.status,'error');
      if(reason==='tree_cleanup') {
        const failure=JSON.parse(rust!.reason!);
        assert.match(failure.cause,/execution.tree_termination_failed/);
        assert.match(failure.cleanup,/rust_tree_cleanup_pending/);
        const scratch=failure.cleanup.split('pending: ')[1];
        assert.ok(scratch.startsWith(join(tmpdir(),'morphir-toolchain-')));
        assert.ok(existsSync(scratch));rmSync(scratch,{recursive:true,force:true});
      } else {assert.ok(rust!.reason!.includes(reason),rust!.reason ?? "Evaluator codec failed");}
    }
  }
  console.log('Evaluator codec: version, cardinality, call identity, status, type, receipt identity, runtime error and injected live disagreement rejected; mock transport only.');
} finally {rmSync(root,{recursive:true,force:true});}
