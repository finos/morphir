import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compilerIdentity, stableVersion} from '../build-provider/capabilities.mjs';
import {excluded, hash, treeIdentity} from '../build-provider/identity.mjs';
import {includeDependencyPath} from '../build-provider/paths.mjs';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.MOON_HOME, 'Set MOON_HOME to the pinned compiler/core installation');
const home = resolve(process.env.MOON_HOME);
const moon = join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const moonc = join(home, 'bin', process.platform === 'win32' ? 'moonc.exe' : 'moonc');
const env = {...process.env, MOON_HOME: home, MOONBIT_NEW_NATIVE: '0', PATH: join(home, 'bin') + delimiter + process.env.PATH};
delete env.MOON_WORK;
assert.ok(execFileSync(moonc, ['-v'], {encoding: 'utf8', env}).trim().startsWith('v' + stableVersion));
assert.match(readFileSync(join(home, 'lib/core/moon.mod'), 'utf8'), /version\s*=\s*"0\.10\.15\+943464bfa"/);
const sdk = resolve(process.env.MORPHIR_FRONTEND_SDK || join(repository, 'pkgs/morphir-sdk'));
assert.match(readFileSync(join(sdk, 'moon.mod'), 'utf8'), /name\s*=\s*"finos\/morphir-sdk"/);
assert.match(readFileSync(join(sdk, 'moon.mod'), 'utf8'), /version\s*=\s*"0\.1\.0"/);
const semanticPin = JSON.parse(readFileSync(join(sdk, 'conformance/bindings.json'), 'utf8')).pin;
assert.equal(semanticPin, 'bc99af69a8b24d391311fae3822a87eafef3c334');
const receipts = resolve(repository, process.env.MORPHIR_FRONTEND_RECEIPTS || '.dev/frontend-acceptance');
mkdirSync(receipts, {recursive: true});
rmSync(join(receipts, 'identity.json'), {force: true});
const workspace = mkdtempSync(join(tmpdir(), 'morphir-frontend-'));
const lanes = [];
try {
  const output = JSON.parse(execFileSync(moon, ['run', 'pkgs/morphir-moonbit-frontend/acceptance', '--target', 'native'], {
    cwd: repository, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216,
  }));
  assert.equal(output.profile, 'moonbit-model-bool-v1');
  assert.equal(output.parserVersion, '0.4.5');
  assert.equal(output.models.length, 11);
  assert.equal(new Set(output.models.map(m => m.id)).size, 11);
  writeFileSync(join(receipts, 'models.json'), JSON.stringify(output, null, 2) + '\n');
  const library = JSON.parse(execFileSync(moon, ['run', 'pkgs/morphir-moonbit-frontend/library-acceptance', '--target', 'native'], {
    cwd: repository, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216,
  }));
  assert.equal(library.language, 'moonbit');
  assert.equal(library.profile, 'moonbit-model-bool-library-v1');
  assert.equal(library.parserVersion, output.parserVersion);
  assert.equal(library.models.length, 6);
  assert.equal(new Set(library.models.map(m => m.id)).size, 6);
  assert.equal(library.models.reduce((n, m) => n + m.entries.length, 0), 13);
  assert.equal(library.models.reduce((n, m) => n + m.entries.reduce((r, e) => r + e.arguments.length, 0), 0), 42);
  assert.equal(library.models.find(m => m.id === 'private').entries.length, 0);
  writeFileSync(join(receipts, 'library-models.json'), JSON.stringify(library, null, 2) + '\n');
  const seedRows = [[false, false], [false, true], [true, false], [true, true]];
  const models = [
    ...output.models.map(model => ({...model, id: 'seed-' + model.id, private: [], entries: [{
      original: 'decide', function: model.function, arguments: seedRows, expected: model.expected, scheme: model.scheme,
    }]})),
    ...library.models.map(model => ({...model, id: 'library-' + model.id})),
  ];
  const sdkIdentity = treeIdentity(sdk);
  cpSync(sdk, join(workspace, 'sdk'), {recursive: true, filter: path => includeDependencyPath(sdk, path, excluded)});
  assert.equal(treeIdentity(join(workspace, 'sdk')), sdkIdentity);
  const members = ['./sdk', './consumer'];
  const imports = ['"finos/morphir-sdk@0.1.0"'];
  const aliases = [];
  const tests = [];
  const privateProbes = [];
  for (const [index, model] of models.entries()) {
    assert.match(model.id, /^(seed|library)-[a-z]+$/);
    const originalModule = 'acceptance/original-' + model.id;
    const original = join(workspace, 'original-' + index);
    const generated = join(workspace, 'generated-' + index);
    mkdirSync(original); mkdirSync(generated);
    writeFileSync(join(original, 'moon.mod'), `name = "${originalModule}"\nversion = "0.0.0"\n`);
    writeFileSync(join(original, 'moon.pkg'), '');
    writeFileSync(join(original, 'original.mbt'), model.source);
    assert.deepEqual(model.artifacts.map(a => a.path).sort(), ['library.mbt', 'moon.mod', 'moon.pkg', 'symbols.10n']);
    for (const artifact of model.artifacts) {
      assert.ok(typeof artifact.content === 'string' || (Array.isArray(artifact.content) && artifact.content.every(b => Number.isInteger(b) && b >= 0 && b <= 255)));
      writeFileSync(join(generated, artifact.path), typeof artifact.content === 'string' ? artifact.content : Buffer.from(artifact.content));
    }
    members.push('./original-' + index, './generated-' + index);
    imports.push(JSON.stringify(originalModule + '@0.0.0'), JSON.stringify(model.module + '@0.1.0'));
    aliases.push(`"${originalModule}" @o${index}`, `"${model.module}" @g${index}`);
    for (const entry of model.entries) {
      assert.match(entry.original, /^[a-zA-Z_][a-zA-Z0-9_]*$/);
      assert.match(entry.function, /^[a-zA-Z_][a-zA-Z0-9_]*$/);
      assert.ok(entry.arguments.length > 0);
      assert.equal(entry.arguments.length, entry.expected.length);
      assert.ok(entry.expected.every(value => typeof value === 'boolean'));
      assert.ok(entry.arguments.every(args => Array.isArray(args) && args.every(value => typeof value === 'boolean')));
      assert.deepEqual(entry.scheme, entry.expected);
      tests.push(`///|\ntest "${model.id}/${entry.original}: original, Scheme and generated agree" {\n` + entry.arguments.map((args, row) =>
        `  let original = @o${index}.${entry.original}(${args.join(', ')})\n  assert_eq(original, ${entry.expected[row]})\n  assert_eq(@g${index}.${entry.function}()${args.map(arg => '(' + arg + ')').join('')}, original)\n`).join('') + '}\n');
    }
    for (const symbol of model.private) {
      for (const [kind, alias, name] of [['original', 'o' + index, symbol.original], ['generated', 'g' + index, symbol.function]]) {
        assert.match(name, /^[a-zA-Z_][a-zA-Z0-9_]*$/);
        privateProbes.push({model: model.id, kind, name, source: `///|\ntest "private access rejected" { ignore(@${alias}.${name}) }\n`});
      }
    }
  }
  mkdirSync(join(workspace, 'consumer'));
  writeFileSync(join(workspace, 'consumer/moon.mod'), `name = "acceptance/consumer"\nversion = "0.0.0"\nimport { ${imports.join(', ')} }\n`);
  writeFileSync(join(workspace, 'consumer/moon.pkg'), `import { ${aliases.join(', ')} }\n`);
  writeFileSync(join(workspace, 'consumer/acceptance_test.mbt'), tests.join('\n'));
  writeFileSync(join(workspace, 'moon.work'), `members = ${JSON.stringify(members)}\n`);
  for (const target of ['js', 'native', 'wasm', 'wasm-gc']) {
    for (const mode of ['debug', 'release']) {
      const args = ['test', '--frozen', '--target', target, '-p', 'acceptance/consumer'];
      if (mode === 'release') args.push('--release');
      const result = spawnSync(moon, args, {cwd: workspace, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216});
      writeFileSync(join(receipts, `${target}-${mode}.log`), result.stdout + '\n' + result.stderr);
      assert.ok(!result.error, result.error?.message);
      assert.equal(result.status, 0, `${target}/${mode}: ${result.stdout}\n${result.stderr}`);
      assert.match(result.stdout, /Total tests: 24, passed: 24, failed: 0/);
      lanes.push({target, mode, tests: 24, truthTableRows: 86, seed: {models: 11, rows: 44}, library: {models: 6, entries: 13, rows: 42}});
      console.log(`Boolean frontend ${target}/${mode}: 11 seed models + 6 libraries, 86 rows passed`);
    }
  }
  const privateAccess = [];
  const probePath = join(workspace, 'consumer/private_access_test.mbt');
  for (const [index, probe] of privateProbes.entries()) {
    writeFileSync(probePath, probe.source);
    const result = spawnSync(moon, ['check', '--frozen', '--target', 'js', './consumer'], {
      cwd: workspace, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216,
    });
    assert.ok(!result.error, result.error?.message);
    writeFileSync(join(receipts, `private-${index}.log`), result.stdout + '\n' + result.stderr);
    assert.notEqual(result.status, 0, `${probe.kind} private value escaped: ${probe.model}`);
    assert.ok((result.stdout + result.stderr).includes(probe.name), `Compiler rejection must identify the attempted private value: ${result.stdout}\n${result.stderr}`);
    privateAccess.push({model: probe.model, kind: probe.kind, name: probe.name, rejected: true});
  }
  rmSync(probePath, {force: true});
  const restored = spawnSync(moon, ['check', '--frozen', '--target', 'js', './consumer'], {
    cwd: workspace, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216,
  });
  assert.ok(!restored.error, restored.error?.message);
  assert.equal(restored.status, 0, restored.stdout + restored.stderr);
  const invalid = mkdtempSync(join(tmpdir(), 'morphir-invalid-visibility-'));
  const originalRejections = [];
  try {
    writeFileSync(join(invalid, 'moon.mod'), 'name = "acceptance/invalid"\nversion = "0.0.0"\n');
    writeFileSync(join(invalid, 'moon.pkg'), '');
    for (const [id, source, diagnostic] of [
      ['visibility', 'priv fn hidden() -> Bool { true }\n', /3005/],
      ['arity', 'pub fn f() -> Bool { g() }\nfn g(x : Bool) -> Bool { x }\n', /Error:/],
      ['unknown', 'pub fn f() -> Bool { missing }\n', /Error:/],
      ['duplicate', 'pub fn f() -> Bool { true }\nfn f() -> Bool { false }\n', /Error:/],
      ['binding-type', 'pub fn f() -> Bool { let x : Bool = 42; x }\n', /4014/],
    ]) {
      writeFileSync(join(invalid, 'invalid.mbt'), source);
      const result = spawnSync(moon, ['check', '--target', 'js'], {cwd: invalid, encoding: 'utf8', env, timeout: 300000});
      assert.ok(!result.error, result.error?.message);
      assert.notEqual(result.status, 0, `Original compiler must reject ${id}`);
      assert.match(result.stdout + result.stderr, diagnostic);
      writeFileSync(join(receipts, `invalid-${id}.log`), result.stdout + '\n' + result.stderr);
      originalRejections.push({id, sourceIdentity: hash(source), rejected: true});
    }
    // Recursion is valid MoonBit syntax and typing, but excluded from this profile.
    writeFileSync(join(invalid, 'invalid.mbt'), 'pub fn f() -> Bool { f() }\n');
    const recursive = spawnSync(moon, ['check', '--target', 'js'], {cwd: invalid, encoding: 'utf8', env, timeout: 300000});
    assert.ok(!recursive.error, recursive.error?.message);
    assert.equal(recursive.status, 0, recursive.stdout + recursive.stderr);
    writeFileSync(join(receipts, 'excluded-recursion.log'), recursive.stdout + '\n' + recursive.stderr);
  } finally { rmSync(invalid, {recursive: true, force: true}); }
  const identities = {
    successful: true, profile: output.profile, parserVersion: output.parserVersion,
    compilerVersion: stableVersion, compilerIdentity: compilerIdentity(home),
    coreIdentity: treeIdentity(join(home, 'lib/core'), {core: true}),
    frontendIdentity: treeIdentity(join(repository, 'pkgs/morphir-moonbit-frontend')),
    generatorIdentity: treeIdentity(join(repository, 'pkgs/morphir-moonbit')),
    parserIdentity: treeIdentity(join(repository, '.mooncakes/moonbitlang/parser')),
    lexerIdentity: treeIdentity(join(repository, '.mooncakes/moonbitlang/lexer')),
    ionIdentity: treeIdentity(join(repository, '.mooncakes/moonrockz/ion')),
    sdk: {identity: sdkIdentity, semanticPin}, node: process.version,
    models: output.models.map(model => ({id: model.id, sourceIdentity: hash(model.source), irIdentity: hash(model.ir), artifactsIdentity: hash(JSON.stringify(model.artifacts))})),
    library: {language: library.language, profile: library.profile,
      models: library.models.map(model => ({id: model.id, sourceIdentity: hash(model.source), irIdentity: hash(model.ir), artifactsIdentity: hash(JSON.stringify(model.artifacts))}))},
    privateAccess, originalRejections, excludedRecursionCompilerAccepted: true, invalidVisibilityRejected: true, lanes,
  };
  writeFileSync(join(receipts, 'identity.json'), JSON.stringify(identities, null, 2) + '\n');
} finally {
  rmSync(workspace, {recursive: true, force: true});
}
