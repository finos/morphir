import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { mckCommand } from '../build-provider/mck.mjs';

const supported = process.platform !== 'win32';
function fixture(body: string, runnerVersion = '0.4.0-beta.12') {
  const root = mkdtempSync(join(tmpdir(), 'morphir-mck-provider-'));
  const executable = join(root, 'morphir backend');
  writeFileSync(executable, `#!${process.execPath}\nif(process.argv.includes('--version')){console.log('morphir ${runnerVersion}');process.exit(0);}\nif(process.argv.slice(2).join(' ')==='--no-banner mck kit status --json'){console.log(JSON.stringify({revision:'${'a'.repeat(40)}',corpusHash:'sha256-${'b'.repeat(64)}',driverContract:2,algorithm:'mck-file-map-sha256/1'}));process.exit(0);}\n${body}\n`, { mode: 0o700 });
  const config = { profile: 'morphir/cli/mck-command', contractVersion: '0.1.0-draft.1',
    pin: { contractVersion: '0.1.0-draft.1', runnerVersion, executable,
      sha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
      sourceRevision: 'a'.repeat(40), origin: 'controlled process fixture' },
    arguments: ['check', 'kit path', '--json'], cwd: root, timeout: 10000, cancelFile: '' };
  return { root, executable, config, dispose: () => rmSync(root, { recursive: true, force: true }) };
}

test('MCK validates the selected version and pin before launching canonical operations', { skip: !supported }, async () => {
  const f = fixture(`require('node:fs').writeFileSync('started','yes');`);
  try {
    const version = await mckCommand({ ...f.config, pin: { ...f.config.pin, runnerVersion: '9.0.0' } });
    assert.equal(version.error, 'mck.unsupported_runner_version'); assert.equal(version.exitCode, 2);
    const digest = await mckCommand({ ...f.config, pin: { ...f.config.pin, sha256: '0'.repeat(64) } });
    assert.equal(digest.error, 'mck.executable_changed'); assert.equal(digest.exitCode, 2);
    assert.equal(existsSync(join(f.root, 'started')), false);
    const node = { ...f.config.pin, executable: process.execPath,
      sha256: createHash('sha256').update(readFileSync(process.execPath)).digest('hex') };
    const mismatch = await mckCommand({ ...f.config, pin: node });
    assert.equal(mismatch.error, 'mck.runner_version_mismatch'); assert.equal(mismatch.exitCode, 2);
    const source = await mckCommand({ ...f.config, pin: { ...f.config.pin, sourceRevision: 'c'.repeat(40) } });
    assert.equal(source.error, 'mck.runner_contract_mismatch'); assert.equal(source.exitCode, 2);
    assert.equal(existsSync(join(f.root, 'started')), false);
  } finally { f.dispose(); }
});

test('MCK still runs a pin saved for beta.10 and checks it against its own version', { skip: !supported }, async () => {
  const saved = fixture(`process.stdout.write('saved pin ran');`, '0.4.0-beta.10');
  try {
    const result = await mckCommand(saved.config);
    assert.equal(result.state, 'completed'); assert.equal(result.exitCode, 0);
    assert.equal(result.stdout, 'saved pin ran');
    assert.equal(result.runner?.runnerVersion, '0.4.0-beta.10');
    // The pin selects the version: a beta.12 pin does not admit this executable.
    const other = await mckCommand({ ...saved.config, pin: { ...saved.config.pin, runnerVersion: '0.4.0-beta.12' } });
    assert.equal(other.error, 'mck.runner_version_mismatch'); assert.equal(other.exitCode, 2);
    const unlisted = await mckCommand({ ...saved.config, pin: { ...saved.config.pin, runnerVersion: '0.4.0-beta.11' } });
    assert.equal(unlisted.error, 'mck.unsupported_runner_version'); assert.equal(unlisted.exitCode, 2);
  } finally { saved.dispose(); }
});

test('MCK preserves canonical argv, stdout, stderr and failed verdict exit status', { skip: !supported }, async () => {
  const f = fixture(`process.stdout.write(JSON.stringify(process.argv.slice(2)));process.stderr.write('diagnostic without newline');process.exitCode=1;`);
  try {
    f.config.arguments = ['workbench', 'run', '--adapter-arg', '', '--adapter-arg', '--json', 'λ 😀', '$(literal)', '--'];
    const starts: string[] = [];
    const result = await mckCommand(f.config, () => false, program => starts.push(program));
    assert.equal(starts.length, 3);
    assert.ok(starts.every(program => program === f.config.pin.executable));
    assert.equal(result.state, 'completed'); assert.equal(result.exitCode, 1);
    assert.deepEqual(JSON.parse(result.stdout), ['--no-banner', 'mck', ...f.config.arguments]);
    assert.equal(result.stderr, 'diagnostic without newline');
    assert.equal(result.runner?.sha256, f.config.pin.sha256);
  } finally { f.dispose(); }
});

test('MCK cancellation before launch does not execute the runner', { skip: !supported }, async () => {
  const f = fixture(`require('node:fs').writeFileSync('started','yes');`);
  try {
    const result = await mckCommand(f.config, () => true);
    assert.equal(result.state, 'cancelled'); assert.equal(result.exitCode, 130);
    assert.equal(existsSync(join(f.root, 'started')), false);
    writeFileSync(join(f.root, 'cancel'), '');
    const file = await mckCommand({ ...f.config, cancelFile: 'cancel' });
    assert.equal(file.exitCode, 130); assert.equal(existsSync(join(f.root, 'started')), false);
  } finally { f.dispose(); }
});

test('MCK cancels running commands and rejects partial or oversized process output', { skip: !supported }, async () => {
  const f = fixture(`require('node:fs').writeFileSync('started','yes');process.stdout.write('{partial');setInterval(()=>{},1000);`);
  try {
    const timer = setInterval(() => { if (existsSync(join(f.root, 'started'))) writeFileSync(join(f.root, 'cancel'), ''); }, 10);
    try {
      const result = await mckCommand({ ...f.config, cancelFile: 'cancel' });
      assert.equal(result.exitCode, 130); assert.equal(result.stdout, '');
    } finally { clearInterval(timer); }
    rmSync(join(f.root, 'cancel'));
    const timeout = await mckCommand({ ...f.config, timeout: 500 });
    assert.equal(timeout.exitCode, 124); assert.equal(timeout.stdout, '');
    const oversize = fixture(`process.stdout.write('x'.repeat(1048577));setInterval(()=>{},1000);`);
    try {
      const result = await mckCommand(oversize.config);
      assert.equal(result.exitCode, 1); assert.match(result.error!, /execution.diagnostic_limit/); assert.equal(result.stdout, '');
    } finally { oversize.dispose(); }
  } finally { f.dispose(); }
});

test('MCK refuses malformed control data on every host', async () => {
  for (const value of [null, {}, { profile: 'morphir/cli/mck-command', contractVersion: '2.0.0' }]) {
    const result = await mckCommand(value);
    assert.equal(result.state, 'refused'); assert.equal(result.exitCode, 2);
  }
});

test('MCK reports an unconfirmed descendant outcome when graceful interruption expires', { skip: !supported }, async () => {
  const f = fixture(`process.on('SIGINT',()=>{});require('node:fs').writeFileSync('started','yes');process.stdout.write('{partial');setInterval(()=>{},1000);`);
  const timer = setInterval(() => { if (existsSync(join(f.root, 'started'))) writeFileSync(join(f.root, 'cancel'), ''); }, 10);
  try {
    const result = await mckCommand({ ...f.config, cancelFile: 'cancel' });
    assert.equal(result.exitCode, 130);
    assert.equal(result.stdout, '');
    assert.match(result.error!, /execution.tree_termination_unconfirmed/);
  } finally { clearInterval(timer); f.dispose(); }
});
