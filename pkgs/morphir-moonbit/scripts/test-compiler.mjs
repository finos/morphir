import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, cpSync, realpathSync, readlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { isWithin, includeDependencyPath } from '../../../apps/morphir/build-provider/paths.mjs';

assert.ok(process.argv[2], 'Supply the SDK source directory as an argument');
const suppliedSdk=resolve(process.argv[2]);
const repository = fileURLToPath(new URL('../../../', import.meta.url));
const coreHome=process.env.MOON_HOME;
assert.ok(coreHome,'Set MOON_HOME to the pinned compiler/core installation');
const moon=join(coreHome,'bin',process.platform==='win32'?'moon.exe':'moon');
const moonc=join(coreHome,'bin',process.platform==='win32'?'moonc.exe':'moonc');
const expectedCompiler = 'v0.10.15+943464bfa';
const coreManifest=readFileSync(join(coreHome,'lib/core/moon.mod'),'utf8');
assert.match(coreManifest,/version\s*=\s*"0\.10\.15\+943464bfa"/);
const compiler = execFileSync(moonc, ['-v'], {encoding:'utf8'}).trim();
assert.ok(compiler.startsWith(expectedCompiler), `Compiler must be ${expectedCompiler}, got ${compiler}`);
const output = JSON.parse(execFileSync(moon, ['run', 'pkgs/morphir-moonbit/acceptance', '--target', 'native'], {cwd:repository, encoding:'utf8', maxBuffer:16777216}));
const workspace = mkdtempSync(join(tmpdir(), 'morphir-generator-'));
const excluded = new Set(['_build','.mooncakes','.git','node_modules']);
function digestTree(root, allowLinks=false) {
  const entries=[];
  const fileDigest=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
  function walk(relative) {
    const children=readdirSync(join(root,relative),{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0);
    for (const entry of children) {
      if (excluded.has(entry.name)) continue;
      const path=relative?relative+'/'+entry.name:entry.name;
      if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) entries.push({path,kind:'file',digest:fileDigest(join(root,path))});
      else if (entry.isSymbolicLink() && allowLinks) {
        const target=realpathSync(join(root,path));
        assert.ok(isWithin(realpathSync(root),target),`Core link escapes its source tree: ${path}`);
        entries.push({path,kind:'link',target:readlinkSync(join(root,path)),digest:fileDigest(target)});
      } else throw new Error(`Unsupported supplied dependency entry ${path}`);
    }
  }
  walk('');
  return createHash('sha256').update(JSON.stringify(entries)).digest('hex');
}

try {
  const sdk = suppliedSdk;
  assert.match(readFileSync(join(sdk,'moon.mod'),'utf8'),/name\s*=\s*"finos\/morphir-sdk"/);
  assert.match(readFileSync(join(sdk,'moon.mod'),'utf8'),/version\s*=\s*"0\.1\.0"/);
  const semanticPin=JSON.parse(readFileSync(join(sdk,'conformance/bindings.json'),'utf8')).pin;
  assert.equal(semanticPin,'bc99af69a8b24d391311fae3822a87eafef3c334');
  const sdkDigest = digestTree(sdk);
  // Supply SDK source directly in an isolated workspace. No registry acquisition.
  cpSync(sdk,join(workspace,'sdk'), {recursive:true,filter:path=>includeDependencyPath(sdk,path,excluded)});
  assert.equal(digestTree(join(workspace,'sdk')),sdkDigest);
  const project = join(workspace,'generated');
  mkdirSync(project);
  for (const artifact of output.artifacts) {
    assert.ok(['moon.mod','moon.pkg','library.mbt','symbols.10n'].includes(artifact.path));
    writeFileSync(join(project,artifact.path),typeof artifact.content==='string'?artifact.content:Buffer.from(artifact.content));
  }
  const requested=join(workspace,'requested');mkdirSync(join(requested,'consumer'),{recursive:true});
  for(const artifact of output.requestedArtifacts)writeFileSync(join(requested,artifact.path),typeof artifact.content==='string'?artifact.content:Buffer.from(artifact.content));
  writeFileSync(join(requested,'consumer/moon.pkg'),`import { "${output.requestedModule}" @requested }\n`);
  writeFileSync(join(requested,'consumer/requested_test.mbt'),`///|\ntest "exact requested name reserves automatic names and retains references" {
    assert_eq(@requested.wanted(),true)
    assert_eq(@requested.main_wanted(),false)
    assert_eq(@requested.copy(),true)
  }\n`);
  const naming=join(workspace,'naming');mkdirSync(join(naming,'consumer'),{recursive:true});
  for(const artifact of output.namingArtifacts)writeFileSync(join(naming,artifact.path),typeof artifact.content==='string'?artifact.content:Buffer.from(artifact.content));
  const namedSymbols=new Map(output.namingSymbols.map(s=>[s.fqname,s.name]));
  assert.equal(namedSymbols.get('naming:main#ready'),'ready');
  assert.equal(namedSymbols.get('naming:main#capture'),'capture');
  writeFileSync(join(naming,'consumer/moon.pkg'),`import { "${output.namingModule}" @named }\n`);
  writeFileSync(join(naming,'consumer/naming_test.mbt'),`///|\ntest "readable public names preserve scope and capture semantics" {
    assert_eq(@named.ready(),true)
    assert_eq(@named.captured_global(),true)
    assert_eq(@named.capture()(false)(true),false)
    assert_eq(@named.capture()(true)(false),true)
    assert_eq(@named.second_capture()(false)(true),false)
    assert_eq(@named.record_capture()(true),true)
    assert_eq(@named.record_capture()(false),false)
    assert_eq(@named.main_copy(),true)
    assert_eq(@named.${namedSymbols.get('naming:other#copy')}(),false)
    assert_eq(@named.${namedSymbols.get('naming:main#if')}(),false)
    assert_eq(@named.${namedSymbols.get('naming:main#if-value')}(),true)
  }\n`);
  writeFileSync(join(workspace,'moon.work'),'members=["./generated","./sdk","./naming","./requested"]\n');
  const symbols = new Map(output.symbols.map(s=>[s.fqname,s]));
  const coverage=JSON.parse(readFileSync(join(repository,'pkgs/morphir-moonbit/sdk-coverage.json'),'utf8'));
  assert.equal(coverage.values.length,coverage.bindingCount);
  const audited=coverage.values.filter(binding=>binding.status==='supported-concrete-instances');
  assert.equal(audited.length,coverage.supportedBindings);
  for (const binding of audited) {
    const name=binding.fqName.slice('morphir/SDK:'.length).replace('#','-');
    assert.ok(symbols.has('pricing:audit#'+name),`Missing compiler fixture for ${binding.fqName}`);
  }
  assert.equal(symbols.get('pricing:quotes#reprice').name,'reprice');
  assert.equal(symbols.get('pricing:quotes#approved').name,'approved');
  const call = name => '@generated.'+symbols.get('pricing:'+name).name+'()';
  const test = `///|
    test "generated scalar API preserves exact values" {
      assert_eq(@integer.to_string(${call('scalars#huge')}), "1234567890123456789012345678901234567890")
      assert_eq(@integer.to_string(${call('other#copy')}), "1234567890123456789012345678901234567890")
      assert_eq(@decimal.to_string(${call('scalars#rate')}), "0.1234")
      assert_eq(${call('scalars#negative-zero')}.reinterpret_as_uint64(), 9223372036854775808UL)
      assert_eq(${call('scalars#tiny')}.reinterpret_as_uint64(), 1UL)
      assert_eq(${call('scalars#label')}.to_units(), [(955).to_uint16(), (55357).to_uint16(), (56832).to_uint16(), (10).to_uint16(), (34).to_uint16(), (92).to_uint16(), (36).to_uint16(), (40).to_uint16(), (102).to_uint16(), (111).to_uint16(), (114).to_uint16(), (98).to_uint16(), (105).to_uint16(), (100).to_uint16(), (100).to_uint16(), (101).to_uint16(), (110).to_uint16(), (41).to_uint16()])
      assert_eq(${call('scalars#letter')}.to_units(), [(55357).to_uint16(), (56832).to_uint16()])
      assert_eq(${call('scalars#enabled')}, true)
      assert_eq(${call('scalars#SDK')}, true)
      assert_eq(${call('scalars#sdk')}, false)
      assert_eq(${call('scalars#nothing')}, ())
      assert_eq(@decimal.to_string(${call('results#total')}), "37.5")
      assert_eq(@decimal.to_string(${call('results#repriced')}), "12.75")
      assert_eq(@decimal.to_string(${call('results#approved-amount')}), "37.5")
      let status : @generated.Status = @generated.Status::Approved(@decimal.from_string("2.5").unwrap())
      match status {
        @generated.Approved(amount) => assert_eq(@decimal.to_string(amount), "2.5")
        @generated.Rejected => fail("readable constructor")
      }
      assert_eq(@decimal.to_string(@generated.sample().price), "12.5")
      assert_eq(@integer.to_string(${call('results#mapped-sum')}), "36")
      assert_eq(@integer.to_string(${call('results#ordered')}), "97")
      assert_eq(@integer.to_string(${call('results#safe-branch')}), "42")
      assert_eq(${call('results#safe-and')}, false)
      let error = try { ignore(${call('results#failure')}); false } catch { @sdk.DivisionByZero => true; _ => false }
      assert_true(error)
      assert_eq(${call('audit#basics-xor')}(true)(false), true)
      assert_eq(${call('audit#basics-power-float')}(9.0)(0.5), 3.0)
      assert_eq(${call('audit#basics-power-float')}(2.0)(-2.0), 0.25)
      assert_eq(@integer.to_string(${call('audit#basics-power')}(@integer.from_int(3))(@integer.from_int(4))), "81")
      assert_eq(${call('audit#basics-less-than-or-equal-float')}(0.0 / 0.0)(0.0), false)
      assert_eq(${call('audit#basics-greater-than-text')}(@sdk.Text::from_string("b"))(@sdk.Text::from_string("aa")), true)
      assert_eq(${call('audit#basics-less-than-character')}(@sdk.Character::from_char('😀'))(@sdk.Character::from_char('\\u{e000}')), true)
      let identity = ${call('audit#basics-identity-function')}
      let captured = ${call('quotes#captured')}(@integer.from_int(10))
      assert_eq(@integer.to_string(identity(captured)(@integer.from_int(1))), "11")
    }
  `;
  writeFileSync(join(project,'acceptance_test.mbt'),test);
  writeFileSync(join(project,'moon.pkg'),readFileSync(join(project,'moon.pkg'),'utf8')+`import { "${output.moduleName}" @generated, "finos/morphir-sdk" @sdk } for "test"\n`);
  const results=[];
  for (const target of ['native','js','wasm','wasm-gc']) {
    const build=spawnSync(moon,['build','--frozen','--target',target],{cwd:workspace,encoding:'utf8'});
    assert.equal(build.status,0,`generated ${target} build: ${build.stdout}\n${build.stderr}`);
    const result=spawnSync(moon,['test','--frozen','--target',target,'-p',output.moduleName],{cwd:workspace,encoding:'utf8'});
    assert.equal(result.status,0,`generated ${target} tests: ${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout,/passed: 1, failed: 0/);
    const namingResult=spawnSync(moon,['test','--frozen','--target',target,'-p',output.namingModule+'/consumer'],{cwd:workspace,encoding:'utf8'});
    assert.equal(namingResult.status,0,`readable naming ${target}: ${namingResult.stdout}\n${namingResult.stderr}`);
    assert.match(namingResult.stdout,/passed: 1, failed: 0/);
    const requestedResult=spawnSync(moon,['test','--frozen','--target',target,'-p',output.requestedModule+'/consumer'],{cwd:workspace,encoding:'utf8'});
    assert.equal(requestedResult.status,0,`requested target names ${target}: ${requestedResult.stdout}\n${requestedResult.stderr}`);
    assert.match(requestedResult.stdout,/passed: 1, failed: 0/);
    results.push(target);
  }
  // A separate consumer cannot name private values, including public values in private IR modules.
  mkdirSync(join(project,'consumer'));
  writeFileSync(join(project,'consumer/moon.pkg'),`import { "${output.moduleName}" @generated }\n`);
  writeFileSync(join(project,'consumer/check.mbt'),`fn accessible() -> Bool raise { ${call('scalars#enabled')} }\n`);
  const positive=spawnSync(moon,['check','--frozen','--target','native'],{cwd:workspace,encoding:'utf8'});
  assert.equal(positive.status,0,positive.stdout+positive.stderr);
  for (const hidden of ['scalars#hidden','internal#secret','internal#hidden-record']) {
    writeFileSync(join(project,'consumer/check.mbt'),`fn forbidden() -> Bool raise { ${call(hidden)} }\n`);
    const result=spawnSync(moon,['check','--frozen','--target','native'],{cwd:workspace,encoding:'utf8'});
    assert.notEqual(result.status,0,`${hidden} was incorrectly exported`);
    assert.ok((result.stdout+result.stderr).includes(symbols.get('pricing:'+hidden).name));
  }
  const coreDigest=digestTree(join(coreHome,'lib/core'),true);
  // Exercise the complete configured pipeline with substantial current and historical IR.
  execFileSync(moon,['build','--target','native'],{cwd:repository,stdio:'pipe'});
  const cli=join(repository,'_build/native/debug/build/morphir/morphir','morphir.exe');
  const fixture=join(workspace,'pipeline');mkdirSync(join(fixture,'src'),{recursive:true});
  writeFileSync(join(fixture,'morphir.toml'),"[project]\nname='Acceptance'\n[frontend]\nlanguage='ir-json'\n");
  const invoke=args=>JSON.parse(execFileSync(cli,['run','.',...args,'--json'],{cwd:fixture,encoding:'utf8',maxBuffer:16777216}));
  const validate=(frontend,target)=>{
    const result=invoke(['--frontend',frontend,'--backend','moonbit','--component','json-identity','--validation','required','--target',target,
      '--build-provider','process','--build-helper',join(repository,'apps/morphir/build-provider/library-build.mjs'),
      '--build-node',process.execPath,'--home',coreHome,'--sdk',sdk,'--timeout','120000']);
    assert.equal(result.successful,true,JSON.stringify(result));assert.equal(result.validated.length,1);
    assert.equal(result.publicationDetails[0].status,'published');
    assert.ok(result.validated[0].evidence.buildIdentity);
  };
  writeFileSync(join(fixture,'src/Main.json'),output.sourceIR);
  validate('ir-json','native');
  invoke(['--frontend','ir-json','--backend','checkpoint','--checkpoint-format','ion-text']);
  const checkpointRoot=join(fixture,'.morphir/out/compile.dest');
  writeFileSync(join(fixture,'src/Main.ion'),readFileSync(join(checkpointRoot,'Main.ion')));
  rmSync(join(fixture,'src/Main.json'));validate('ion-text','js');
  invoke(['--frontend','ion-text','--backend','checkpoint','--checkpoint-format','ion-binary']);
  writeFileSync(join(fixture,'src/Main.ionb'),readFileSync(join(checkpointRoot,'Main.ionb')));
  rmSync(join(fixture,'src/Main.ion'));validate('ion-binary','wasm-gc');rmSync(join(fixture,'src/Main.ionb'));
  for (const historical of output.historicalSources) {
    writeFileSync(join(fixture,'src/Main.json'),historical);validate('ir-json','wasm');
  }
  console.log(JSON.stringify({successful:true,compiler,compilerDigest:createHash('sha256').update(readFileSync(moonc)).digest('hex'),coreDigest,sdk:{module:'finos/morphir-sdk',version:'0.1.0',treeDigest:sdkDigest,semanticPin:'bc99af69a8b24d391311fae3822a87eafef3c334'},generatedModule:output.moduleName,targets:results,privateAccessChecked:true,readablePublicConsumer:true,declaredTargetNamesConsumer:true,captureAndRecoveryChecked:true,sdkAdapters:audited.length,sdkSpecializationFixtures:output.symbols.filter(s=>s.fqname.startsWith("pricing:audit#")).length,pipelineFormats:['morphir-json','ion-text','ion-binary'],historicalVersions:[1,2,3]}));
} finally { rmSync(workspace,{recursive:true,force:true}); }
