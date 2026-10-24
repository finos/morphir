import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
import {parse} from '@std/semver';
import {openConnectedOriginals, type ConnectedOriginalsEvent, type OriginalPayload} from '../browser/connected-originals.ts';
import {ModelOriginalsConnectionLimits} from '../browser/model-originals-session.ts';
import type {Hasher} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';

/** A genuine receiver-owned queued stage; this fixture issues no grants or stage constructors. */
export async function routingFixture(makeHash: () => Hasher, hostPath = fileURLToPath(new URL('./originals-fixture-host.ts', import.meta.url))) {
  const child = spawn('bun', [hostPath], {stdio: ['pipe', 'pipe', 'pipe']});
  const exited = once(child, 'exit');
  let stderr = '';
  child.stderr.on('data', chunk => {stderr = (stderr + String(chunk)).slice(-4096);});
  const lines = createInterface({input: child.stdout});
  let opening: ReturnType<typeof openConnectedOriginals> | undefined;
  let live = true, takes = 0, disposals = 0;
  let handed: OriginalPayload | undefined;
  const previous = globalThis.morphirWorkbench;
  let restored = false;
  async function finish() {
    if (restored) return;
    restored = true;
    live = false; opening?.dispose(); handed = undefined;
    if (previous === undefined) Reflect.deleteProperty(globalThis, 'morphirWorkbench');
    else globalThis.morphirWorkbench = previous;
    child.stdin.end();
    const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
    try {
      const [code, signal] = await exited;
      assert.equal(signal, null, stderr);
      assert.equal(code, 0, stderr);
    } finally {clearTimeout(timeout); lines.close();}
  }
  const startupTimer = setTimeout(() => child.kill('SIGKILL'), 10000);
  try {
    const first = await Promise.race([
      once(lines, 'line').then(([line]) => String(line)),
      exited.then(() => {throw new Error(`Originals fixture exited before ready: ${stderr}`);}),
    ]);
    clearTimeout(startupTimer);
    let received: Extract<ConnectedOriginalsEvent, {kind: 'received'}> | undefined;
    let failure: Error | undefined;
    opening = openConnectedOriginals({base: new URL(first),
      limits: ModelOriginalsConnectionLimits.create({manifestBytes: 128 * 1024}), makeHash,
      current: () => live, receive(event) {
        if (event.kind === 'failed') failure = new Error(event.message);
        if (event.kind !== 'received') return;
        const actualTake = event.stage.take.bind(event.stage);
        event.stage.take = adopt => {
          ++takes;
          return actualTake(payload => {handed = payload; adopt(payload);});
        };
        received = event;
      }});
    await opening.whenSettled();
    assert.equal(opening.view(), 'sources', failure?.message ?? "Originals routing failed");
    assert.equal(opening.chooseSource(1), 'started');
    await opening.whenSettled();
    assert.equal(opening.view(), 'projects', failure?.message ?? "Originals routing failed");
    assert.equal(opening.chooseProject(1), 'started');
    await opening.whenSettled();
    assert.equal(opening.view(), 'queued', failure?.message ?? "Originals routing failed");
    assert(received, 'Actual strict release and receiver completion must precede the routing fixture');
    const owner = opening;
    const actualDispose = owner.dispose.bind(owner);
    owner.dispose = () => {++disposals; actualDispose();};
    // Application boundary only. The same actual owner and validated payload
    // cross into the real MoonBit handler; no successful result is fabricated.
    globalThis.morphirWorkbench = {
      ...previous,
      connected: true, mode: 'connected-originals',
      disposeOriginals(actual) {assert.equal(actual, owner); actual.dispose();},
      originalHeaderParts(payload) {
        if (payload.sourceFormatVersion.status === 'not-reported') return [];
        const release = parse(payload.sourceFormatVersion.release);
        return [release.major, release.minor, release.patch];
      },
    } as typeof globalThis.morphirWorkbench;
    return {owner, event: received, finish, get takes() {return takes;}, get disposals() {return disposals;},
      corruptHandedBytes() {assert(handed); for (const file of handed.files) file.bytes.fill(0);}};
  } catch (error) {
    clearTimeout(startupTimer);
    await finish();
    throw error;
  }
}
