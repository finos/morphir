import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? `.dev/build-model-cli`);
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
const runner = join(repo, 'pkgs/morphir-host/runners/wasm.mjs');
const root = mkdtempSync(join(tmpdir(), 'morphir-model-inventory-'));
const fixture = join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/yaml/literal42-tree');
const expected = JSON.parse(readFileSync(join(fixture, 'expectation.json'), 'utf8'));
const node = process.versions.bun ? 'node' : process.execPath;
const unavailable: string[] = [];
function tree(name: string) {
  mkdirSync(join(root, name));
  for (const file of expected.files) {
    mkdirSync(join(root, name, file.path, '..'), {recursive: true});
    cpSync(join(fixture, file.path), join(root, name, file.path));
  }
}
function invoke(path: string, ok = false, extra: string[] = [], trace: boolean | 'cancel' = false) {
  const args = ['model', extra.length ? 'export-original' : 'inspect', path, '--json', ...extra];
  const prefix = target === 'native' ? [] : target === 'js' ? [binary] : [runner, binary];
  const result = spawnSync(target === 'native' ? binary : node, [...prefix, ...args], {
    cwd: root, env: {...process.env, ...(target === 'native' ? {PATH: ''} : {}), HOME: root, USERPROFILE: root, DISPLAY: '', WAYLAND_DISPLAY: '',
      ...(trace ? {NODE_OPTIONS: `--import=${pathToFileURL(join(root, 'trace.mjs')).href}`} : {})},
    encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, trace === 'cancel' ? 130 : ok ? 0 : 2, `${path}: ${result.stdout}\n${result.stderr}`);
  return JSON.parse(result.stdout);
}
try {
  tree('small');
  const opaque = Buffer.from([0, 255, 13, 10, 0]);
  writeFileSync(join(root, 'small/opaque.bin'), opaque);
  writeFileSync(join(root, 'small/astral-😀.txt'), 'exact\r\n');
  writeFileSync(join(root, 'small/\uFEFFbom.txt'), 'BOM is part of the name');
  mkdirSync(join(root, 'small/empty/nested'), {recursive: true});
  const inspection = invoke('small', true);
  assert.deepEqual(JSON.parse(inspection.normalizedIr), expected.expectedNormalizedIr);
  const exported = invoke('small', true, ['--output', 'saved']);
  assert.ok(exported.directories.includes('empty/nested'));
  assert.ok(statSync(join(root, 'saved/originals/empty/nested')).isDirectory());
  assert.deepEqual(readFileSync(join(root, 'saved/originals/opaque.bin')), opaque);
  assert.equal(readFileSync(join(root, 'saved/originals/astral-😀.txt'), 'utf8'), 'exact\r\n');
  assert.equal(readFileSync(join(root, 'saved/originals/\uFEFFbom.txt'), 'utf8'), 'BOM is part of the name');
  for (const file of expected.files) assert.deepEqual(readFileSync(join(root, 'saved/originals', file.path)), readFileSync(join(fixture, file.path)));

  // Enumeration must stop at the 8193rd name, before capture can open a file.
  mkdirSync(join(root, 'wide'));
  for (let i = 0; i < 8300; i++) writeFileSync(join(root, 'wide', `entry-${String(i).padStart(5, '0')}`), '');
  if (target === 'js') writeFileSync(join(root, 'trace.mjs'), `
    import fs from 'node:fs';
    const original=fs.opendirSync; let reads=0,opens=0,closes=0;
    fs.readdirSync=()=>{throw new Error('Unbounded directory read forbidden')};
    fs.opendirSync=(...args)=>{opens++;const d=original(...args),read=d.readSync.bind(d),close=d.closeSync.bind(d);
      d.readSync=()=>{reads++;return read()};d.closeSync=()=>{closes++;return close()};return d};
    process.on('exit',()=>fs.writeFileSync(${JSON.stringify(join(root, 'trace.json'))},JSON.stringify({reads,opens,closes})));
  `);
  const wide = invoke('wide', false, [], target === 'js');
  assert.match(wide.error, /Model input directory entries/);
  if (target === 'js') assert.deepEqual(JSON.parse(readFileSync(join(root, 'trace.json'), 'utf8')), {reads: 8193, opens: 1, closes: 1});
  invoke('wide', false, ['--output', 'refused']);
  assert.equal(existsSync(join(root, 'refused')), false);
  if (target === 'js') {
    writeFileSync(join(root, 'trace.mjs'), `
      import fs from 'node:fs'; const open=fs.opendirSync; let closes=0;
      fs.opendirSync=(...args)=>{const d=open(...args),close=d.closeSync.bind(d);
        d.readSync=()=>{throw new Error('injected-directory-read')};d.closeSync=()=>{closes++;return close()};return d};
      process.on('exit',()=>fs.writeFileSync(${JSON.stringify(join(root, 'trace.json'))},JSON.stringify({closes})));
    `);
    assert.match(invoke('small', false, [], true).error, /injected-directory-read/);
    assert.deepEqual(JSON.parse(readFileSync(join(root, 'trace.json'), 'utf8')), {closes: 1});
    writeFileSync(join(root, 'trace.mjs'), `
      import fs from 'node:fs'; const open=fs.opendirSync; let closes=0;
      globalThis.__morphirInterrupt=new Int32Array(new SharedArrayBuffer(4));Atomics.store(globalThis.__morphirInterrupt,0,1);
      fs.opendirSync=(...args)=>{const d=open(...args),close=d.closeSync.bind(d);
        d.closeSync=()=>{closes++;return close()};return d};
      process.on('exit',()=>fs.writeFileSync(${JSON.stringify(join(root, 'trace.json'))},JSON.stringify({closes})));
    `);
    assert.equal(invoke('small', false, [], 'cancel').code, 'execution.cancelled');
    assert.deepEqual(JSON.parse(readFileSync(join(root, 'trace.json'), 'utf8')), {closes: 1});
  }

  mkdirSync(join(root, 'files'));
  for (let i = 0; i < 4097; i++) writeFileSync(join(root, 'files', `file-${i}`), '');
  assert.match(invoke('files').error, /Model input file count/);
  mkdirSync(join(root, 'directories'));
  for (let i = 0; i < 4097; i++) mkdirSync(join(root, 'directories', `dir-${i}`));
  assert.match(invoke('directories').error, /Model input directory count/);
  // Pending ancestor names consume the same aggregate budget as child names.
  for (let i = 0; i < 4096; i++) writeFileSync(join(root, 'directories/dir-0', `file-${i}`), '');
  assert.match(invoke('directories').error, /Model input directory entries/);
  let deep = 'deep';
  for (let i = 0; i < 130; i++) { mkdirSync(join(root, deep)); deep += '/d'; }
  const depthRefusal = invoke('deep').error;
  if (process.platform === 'win32' && target === 'native' && depthRefusal === 'directory.open_failed') {
    // The Win32 enumerator reaches MAX_PATH before the application depth cap.
    // This still requires a parseable refusal and exit 2, not a process failure.
    assert.ok(resolve(root, deep).length > 260);
    unavailable.push('native Windows host path-length limit precedes the application-depth limit');
  } else {
    // The shared OriginalPath validator can refuse component depth before visit.
    assert.match(depthRefusal, /depth|InvalidFilename/);
  }
  mkdirSync(join(root, 'bytes'));
  writeFileSync(join(root, 'bytes/large'), Buffer.alloc(16777217));
  assert.match(invoke('bytes').error, /limit|bytes|large/i);
  const longParent = `path-text/${'p'.repeat(100)}`;
  mkdirSync(join(root, longParent), {recursive: true});
  for (let i = 0; i < 4096; i++) writeFileSync(join(root, longParent, String(i).padStart(160, 'x')), '');
  assert.match(invoke('path-text').error, /Model input path text/);
  tree('links');
  symlinkSync(resolve(root, 'small'), join(root, 'links/escape'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.match(invoke('links').error, /link|special/i);
  invoke('missing');
  mkdirSync(join(root, 'invalid'));
  writeFileSync(join(root, 'invalid/CON'), '');
  invoke('invalid');
  if (process.platform !== 'win32') {
    mkdirSync(join(root, 'invalid-utf8'));
    let created = false;
    try {
      writeFileSync(Buffer.concat([Buffer.from(join(root, 'invalid-utf8/')), Buffer.from([255])]), '');
      created = true;
    } catch (error) {
      if (!(error instanceof Error && 'code' in error && error.code === 'EILSEQ')) throw error;
      unavailable.push('filesystem rejects invalid UTF-8 names before capture');
    }
    if (created) invoke('invalid-utf8');
    if (process.getuid?.() !== 0) {
      mkdirSync(join(root, 'unreadable'));
      chmodSync(join(root, 'unreadable'), 0);
      try { invoke('unreadable'); } finally { chmodSync(join(root, 'unreadable'), 0o700); }
    }
  }
  console.log(`Inventory ${target}: exact bytes/empty directories, enumeration before accumulation, file/directory/path-text/byte limits, links, missing inputs and portable names passed.`);
  for (const reason of unavailable) console.log(`Unavailable fixture: ${reason}.`);
} finally { rmSync(root, {recursive: true, force: true}); }
