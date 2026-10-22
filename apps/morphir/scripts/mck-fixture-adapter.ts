// Transport fixtures only. Every response comes from parent-owned frozen data,
// never from the implementation under test. This does not claim codec support.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { createInterface } from 'node:readline';

const [mode, path, behavior = 'pass', witness] = process.argv.slice(2);
assert.ok(path && ['replay', 'node-address'].includes(mode!));
interface Exchange { request: Record<string, unknown>; response?: Record<string, unknown> }
const exchanges: Exchange[] = [];
if (mode === 'replay') {
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/).filter(Boolean)) {
    const entry = JSON.parse(line);
    if (entry.dir === 'request') exchanges.push({ request: entry.message });
    else if (entry.dir === 'response') exchanges.at(-1)!.response = entry.message;
    else throw Error('Unknown frozen transcript entry');
  }
} else {
  const corpus = JSON.parse(readFileSync(path, 'utf8'));
  assert.equal(corpus.contractVersion, '0.1.0-draft.1');
  exchanges.push({ request: { op: 'capabilities' }, response: {
    suite: 'node-address', contractVersion: corpus.contractVersion, implementation: 'frozen-fixture',
    implementationVersion: '1.0.0', operations: ['resolve'],
  } });
  for (const item of corpus.cases) {
    const input = readFileSync(resolve(dirname(path), item.input), 'utf8');
    exchanges.push({ request: { op: 'resolve', input, uri: item.uri }, response: item.expected.outcome === 'resolved'
      ? { ok: true, ...item.expected, canonicalUri: item.uri } : { ok: false, ...item.expected } });
  }
  exchanges.push({ request: { op: 'exit' } });
}
let index = 0, changed = false;
for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  const actual = JSON.parse(line), expected = exchanges[index++];
  assert.ok(expected, 'Unexpected request after the frozen session');
  const request: Record<string, unknown> = { ...expected.request, id: actual.id };
  if (mode === 'replay') {
    assert.equal(expected.request.id, actual.id);
    // The maintained driver negotiates v2; the historical observation stays v1.
    if (index === 1 && expected.request.op === 'capabilities' && actual.contractVersion === '2.0.0-draft.1')
      request.contractVersion = actual.contractVersion;
  }
  assert.deepEqual(actual, request, 'Request differs from the fixed corpus/transcript');
  if (!expected.response) process.exit(0);
  if (behavior === 'hang' && index === 2) {
    assert.ok(witness); writeFileSync(witness, JSON.stringify({ pid: process.pid }));
    await new Promise(() => { setInterval(() => {}, 1000); });
  }
  if (behavior === 'partial' && index === 2) { process.stdout.write('{"id":'); process.exit(0); }
  const response: Record<string, unknown> = { ...expected.response, id: actual.id };
  if (behavior === 'fail' && index > 1 && !changed) {
    changed = true;
    if (mode === 'replay' && response.canonical) response.canonical = { json: 'null', yaml: 'null' };
    else response.ok = false;
  }
  process.stdout.write(JSON.stringify(response) + '\n');
}
assert.equal(index, exchanges.length, 'Session closed before the frozen transcript ended');
