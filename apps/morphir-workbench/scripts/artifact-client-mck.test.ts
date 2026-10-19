import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';

const adapter = process.env.MORPHIR_WORKBENCH_ARTIFACT_CLIENT_ADAPTER;
if (!adapter || !isAbsolute(adapter)) throw new Error('Set MORPHIR_WORKBENCH_ARTIFACT_CLIENT_ADAPTER to the checked absolute adapter bundle.');
if (!process.env.MORPHIR_WORKBENCH_MCK_JSON) throw new Error('Set MORPHIR_WORKBENCH_MCK_JSON to the compiled production framing codec.');
const version = '0.1.0-draft.28';
const capability = (id = 1) => JSON.stringify({ id, op: 'capabilities', suite: 'workbench', contractVersion: version });
const exit = '{"op":"exit"}\n';
const limit = 1048576 + 1024;

async function run(source: string | Buffer): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [adapter!], {
      env: { ...process.env, MORPHIR_WORKBENCH_ARTIFACT_CLIENT_BROWSER: '0' }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    const output: Buffer[] = [], errors: Buffer[] = []; let total = 0;
    const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('Owned framing adapter exceeded 10 seconds.')); }, 10000);
    const collect = (into: Buffer[]) => (chunk: Buffer) => {
      total += chunk.byteLength;
      if (total > 65536) { child.kill('SIGKILL'); reject(new Error('Unexpected oversized framing-test output.')); }
      else into.push(chunk);
    };
    child.stdout.on('data', collect(output)); child.stderr.on('data', collect(errors));
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('close', code => { clearTimeout(timer); resolve({ code, stdout: Buffer.concat(output).toString(), stderr: Buffer.concat(errors).toString() }); });
    child.stdin.on('error', () => {}); // A refused frame may close stdin before its write finishes.
    child.stdin.end(source);
  });
}
function refused(result: Awaited<ReturnType<typeof run>>) {
  assert.equal(result.code, 1); assert.equal(result.stdout, '');
  assert.equal(result.stderr, 'Artifact client MCK infrastructure failure.\n');
}

test('batched negotiation and exit retain independent correlation IDs and stop cleanly', async () => {
  const result = await run(capability(1) + '\n' + capability(2) + '\n' + exit);
  assert.equal(result.code, 0); assert.equal(result.stderr, '');
  const responses = result.stdout.trim().split('\n').map(line => JSON.parse(line) as { id: number; binding: string; operations: string[] });
  assert.deepEqual(responses.map(response => response.id), [1, 2]);
  for (const response of responses) {
    assert.equal(response.binding, 'morphir-moonbit-artifact-client-node');
    assert.deepEqual(response.operations, ['artifact-client']);
  }
});

test('the complete frame byte bound accepts its exact boundary across pipe chunks', async () => {
  const frame = ' '.repeat(limit - Buffer.byteLength(capability())) + capability();
  assert.equal(Buffer.byteLength(frame), limit);
  const result = await run(frame + '\n' + exit);
  assert.equal(result.code, 0); assert.equal(result.stderr, '');
  assert.equal((JSON.parse(result.stdout) as { id: number }).id, 1);
});

test('one extra complete frame byte refuses before any reply', async () => {
  const frame = ' '.repeat(limit + 1 - Buffer.byteLength(capability())) + capability();
  refused(await run(frame + '\n'));
});

test('duplicate envelope members are rejected by the actual production codec', async () => {
  refused(await run(capability().replace('"id":1', '"id":1,"id":2') + '\n'));
});

test('unexpected envelope members and wrong selected drafts refuse', async () => {
  refused(await run(capability().replace('}', ',"unexpected":true}') + '\n'));
  refused(await run(capability().replace(version, '0.1.0-draft.27') + '\n'));
});

test('unsafe IDs and unpaired escaped Unicode refuse', async () => {
  refused(await run(capability().replace('"id":1', '"id":9007199254740993') + '\n'));
  refused(await run(capability().replace('workbench', '\\ud800') + '\n'));
});

test('invalid UTF-8 refuses without replacement decoding', async () => {
  refused(await run(Buffer.concat([Buffer.from(capability()), Buffer.from([0xe2, 0x82, 0x0a])])));
});

test('an incomplete final line and invalid exit ID both fail rather than acknowledge', async () => {
  refused(await run(capability()));
  refused(await run('{"op":"exit","id":0}\n'));
});
