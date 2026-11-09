import assert from 'node:assert/strict';
import test from 'node:test';
import {spawn} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {needsTerminalWorker} from './terminal-worker.mjs';

test('leading global controls keep interruptible commands in the owned worker', () => {
  for (const command of ['run', 'compile', 'execute', 'verify', 'conform', 'worksheet', 'eval', 'notebook', 'connected', 'model', 'generate', 'mck', 'workspace', 'project', 'toolchain', 'extension']) {
    assert.ok(needsTerminalWorker(['--json', '--profiles', 'metrics', '--log-level=trace', '--config', 'settings.toml', '--isolated', '--discovery-boundary', '.', '--suppress-warning=config.yaml_beside_toml', command]));
  }
});

test('control values and opaque child tokens never become the leading command', () => {
  assert.equal(needsTerminalWorker(['--config', 'worksheet']), false);
  assert.equal(needsTerminalWorker(['--profiles', 'model', 'unknown']), false);
  assert.equal(needsTerminalWorker(['unknown', 'run', 'worksheet', '--profiles', 'metrics']), false);
  assert.equal(needsTerminalWorker(['--', 'worksheet']), false);
  assert.equal(needsTerminalWorker(['--json', '--help']), false);
  assert.equal(needsTerminalWorker(['--log-level', 'debug', 'mck', 'check', '--profiles', '', '--']), true);
});

async function quitProbe(syntheticWindowsEvent: boolean) {
  const directory = mkdtempSync(join(tmpdir(), 'morphir-worker-quit-'));
  const entry = join(directory, 'entry.mjs');
  const ready = join(directory, 'ready');
  writeFileSync(entry, `
import {terminalWorker} from ${JSON.stringify(new URL('./terminal-worker.mjs', import.meta.url).href)};
import {existsSync,writeFileSync} from 'node:fs';
if(!terminalWorker(new URL(import.meta.url),process.argv.slice(2))) {
  const flag=globalThis.__morphirInterrupt;
  process.stdout.write('ready\\n');
  writeFileSync(${JSON.stringify(ready)},'ready');
  while(Atomics.load(flag,0)===0) Atomics.wait(flag,0,0,25);
  process.stdout.write(Atomics.load(flag,0)+':'+flag.byteLength+'\\n');
  process.exitCode=131;
} else if(${syntheticWindowsEvent}) {
  if(process.listenerCount('SIGBREAK')!==1) throw new Error('SIGBREAK owner missing');
  const timer=setInterval(()=>{if(existsSync(${JSON.stringify(ready)})){clearInterval(timer);process.emit('SIGBREAK');}},10);
}
`);
  const env = {...process.env};
  delete env.NODE_OPTIONS;
  delete env.NODE_PATH;
  const child = spawn(process.execPath, [entry, 'worksheet'], {cwd: directory, env, stdio: ['pipe', 'pipe', 'pipe']});
  let stdout = '', stderr = '', finished = false;
  child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
  child.stdin.on('error', error => { if ((error as NodeJS.ErrnoException).code !== 'EPIPE') throw error; });
  const closed = new Promise<{code: number | null; signal: NodeJS.Signals | null}>((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => { finished = true; resolve({code, signal}); });
  });
  const deadline = setTimeout(() => child.kill('SIGKILL'), 8000);
  try {
    while (!stdout.includes('ready\n') && !finished) await new Promise(resolve => setTimeout(resolve, 10));
    assert.ok(stdout.includes('ready\n'), stdout + stderr);
    if (!syntheticWindowsEvent) assert.ok(child.kill('SIGQUIT'));
    const result = await closed;
    assert.deepEqual(result, {code: 131, signal: null}, stdout + stderr);
    assert.equal(stdout, 'ready\n3:4\n', 'Quit uses the existing value and four-byte shared flag');
    assert.equal(stderr, '');
  } finally {
    clearTimeout(deadline);
    child.stdin.destroy();
    if (!finished) { child.kill('SIGKILL'); await closed; }
    rmSync(directory, {recursive: true, force: true});
  }
}

test('real SIGQUIT reaches the owned worker and exits without stdin EOF', {skip: process.platform === 'win32'}, async () => {
  await quitProbe(false);
});

test('Windows SIGBREAK event registration routes the existing Quit value', {skip: process.platform !== 'win32'}, async () => {
  // This qualifies registration/probe routing, not Windows console delivery.
  await quitProbe(true);
});
