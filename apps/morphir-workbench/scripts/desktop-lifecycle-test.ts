import assert from 'node:assert/strict';
import { spawn, execFile, type ChildProcess } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { promisify } from 'node:util';
import { chromium, type Browser, type Page } from 'playwright';
import type { NativeDescriptor, NativeReply } from '../browser/contracts.ts';
import type { Identity, Receipt, SchemeSubmission } from './execution-contracts.ts';

const run = promisify(execFile);
interface ProcessRow { pid: number; parent: number; state: string; born: string; command: string; }
interface HeldExecution { accepted: SchemeSubmission; worker: ProcessRow; running: Receipt; }
type Lifecycle = 'reload' | 'session.close' | 'normal-application-quit';
interface Phase {
  lifecycle: Lifecycle; worker: ProcessRow; identity: Identity; running: Receipt;
  workerRemoved: boolean; confirmedAt: 'replacement-session-reply' | 'session-close-reply' | 'normal-application-exit';
}
const startedAt = new Date().toISOString();
const evidence = resolve(process.argv[3] ?? '.dev/campaign-completion/lifecycle-agent');
assert.equal(process.platform, 'darwin', 'This acceptance currently qualifies macOS only');
assert.equal(process.arch, 'arm64', 'This acceptance currently qualifies Apple Silicon only');

async function inventory(): Promise<ProcessRow[]> {
  const { stdout } = await run('ps', ['-axo', 'pid=,ppid=,stat=,lstart=,command='], { maxBuffer: 8 * 1024 * 1024 });
  return stdout.split('\n').flatMap(line => {
    const found = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(.*)$/);
    return found ? [{ pid: Number(found[1]), parent: Number(found[2]), state: found[3]!, born: found[4]!, command: found[5]! }] : [];
  });
}
function sameProcess(current: ProcessRow | undefined, retained: ProcessRow) {
  // Command and parent may change after exit or reparenting. Keep tracking the
  // initially verified OS identity until that row is actually removed/reaped.
  return current?.pid === retained.pid && current.born === retained.born;
}
const isWorker = (row: ProcessRow, parent: number) => row.parent === parent && row.command === `${executable} --morphir-native-worker`;
function descendants(rows: ProcessRow[], parent: number) {
  const owners = new Set([parent]);
  let previous = 0;
  while (previous !== owners.size) { previous = owners.size; for (const row of rows) if (owners.has(row.parent)) owners.add(row.pid); }
  return rows.filter(row => row.pid !== parent && owners.has(row.pid));
}
async function until<T>(read: () => Promise<T | null>, description: string, milliseconds = 15000): Promise<T> {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    const value = await read(); if (value !== null) return value;
    await pause(10);
  }
  throw new Error(`Timed out: ${description}`);
}
async function removed(worker: ProcessRow) {
  await until(async () => sameProcess((await inventory()).find(row => row.pid === worker.pid), worker) ? null : true,
    `owned worker ${worker.pid} must leave the OS process table`);
}

async function processIdentityRegression() {
  // Keep an actual exited child unreaped. macOS changes its ps command to
  // "<defunct>", but the retained PID and birth still identify the same row.
  const directory = await mkdtemp(join(tmpdir(), 'morphir-process-identity-'));
  const source = join(directory, 'owned-zombie.c'), fixture = join(directory, 'owned-zombie');
  let owner: ChildProcess | undefined;
  let triggered = false;
  try {
    await writeFile(source, `#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
int main(void) {
  int wake[2]; if (pipe(wake)) return 1;
  pid_t child = fork(); if (child < 0) return 2;
  if (!child) { close(wake[1]); char byte; if (read(wake[0], &byte, 1) != 1) _exit(3); _exit(0); }
  close(wake[0]); printf("%d\\n", child); fflush(stdout);
  int command;
  while ((command = getchar()) != EOF) {
    if (command == 'x') { char byte = 'x'; if (write(wake[1], &byte, 1) != 1) return 4; }
    if (command == 'r') { int status; if (waitpid(child, &status, 0) != child) return 5; return WIFEXITED(status) ? WEXITSTATUS(status) : 6; }
  }
  return 7;
}
`);
    await run('clang', ['-Wall', '-Wextra', '-Werror', source, '-o', fixture]);
    owner = spawn(fixture, [], { stdio: ['pipe', 'pipe', 'pipe'] });
    assert.ok(owner.pid);
    const exit = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((resolve, reject) => {
      owner!.once('error', reject); owner!.once('exit', (code, signal) => resolve({ code, signal }));
    });
    const retained = await until(async () => (await inventory()).find(row => row.parent === owner!.pid && row.command === fixture) ?? null,
      'the fixture owner must spawn its exact child executable');
    owner.stdin!.write('x'); triggered = true;
    const zombie = await until(async () => (await inventory()).find(row => row.pid === retained.pid && row.born === retained.born && row.state.includes('Z')) ?? null,
      'owned exited child remains unreaped in the actual OS table');
    assert.notEqual(zombie.command, retained.command, 'The fixture demonstrates macOS changing command text on exit');
    let removalObserved = false;
    const removal = removed(retained).then(() => { removalObserved = true; });
    await pause(100);
    assert.equal(removalObserved, false, 'An exited but unreaped worker is still present; changed command text must not prove removal');
    owner.stdin!.write('r');
    await removal;
    assert.deepEqual(await exit, { code: 0, signal: null });
    await mkdir(evidence, { recursive: true });
    await writeFile(join(evidence, 'process-identity-regression.json'), JSON.stringify({
      retained, zombie, removalObservedOnlyAfterReap: removalObserved, ownerExit: { code: 0, signal: null },
    }, null, 2) + '\n');
  } finally {
    if (owner?.exitCode === null && owner.signalCode === null) {
      // Only this fixture's parent receives commands; it wakes and reaps its
      // own child even when the assertion above fails.
      owner.stdin?.end(triggered ? 'r' : 'xr');
      await until(async () => owner!.exitCode !== null || owner!.signalCode !== null ? true : null,
        'fixture cleanup reaps its child', 5000).catch(() => { owner!.kill('SIGKILL'); });
    }
    await rm(directory, { recursive: true, force: true });
  }
}

await processIdentityRegression();
if (process.argv[2] === '--process-identity-regression') {
  console.log(`Actual macOS unreaped-child regression passed; evidence ${evidence}`);
  process.exit(0);
}
assert.ok(process.argv[2], 'Usage: bun --check desktop-lifecycle-test.ts <packaged-app.app> [evidence-directory]');
const appPath = await realpath(process.argv[2]);
const executable = await realpath(join(appPath, 'Contents/MacOS/morphir-workbench'));
await mkdir(evidence, { recursive: true });
async function native<T>(page: Page, operation: string, sessionId: string | null, payload?: unknown): Promise<NativeReply<T>> {
  const source = await page.evaluate(async ({ operation, sessionId, payload }) => {
    const frame = { profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation,
      ...(sessionId === null ? {} : { sessionId }), ...(payload === undefined ? {} : { payload }) };
    const reply = await window.__MoonBit__!.core!.invokeOp!('app:workbench_native', JSON.stringify(frame));
    const checked = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({
      op: 'native-policy-response', source: reply, operation, sessionId,
    })));
    if (!checked.ok) throw new Error(`Actual native reply failed its production codec: ${checked.code}`);
    return JSON.stringify(checked.value);
  }, { operation, sessionId, payload });
  return JSON.parse(source);
}
function value<T>(reply: NativeReply<T>): T { assert.ok(reply.ok, JSON.stringify(reply)); return reply.value; }
const identityBody = (identity: Identity) => ({ contractVersion: '0.2.0-draft.1', identity });

// Both definitions are ordinary typed Morphir IR. A bounded bulk argument gives
// the OS observer time to stop a real worker, without replacing its executable.
const int = 'morphir/SDK:basics#int';
const list = { Reference: ['morphir/SDK:list#list', int] };
const model = JSON.stringify({ formatVersion: 4, distribution: { Library: { packageName: 'lifecycle', dependencies: {}, def: { modules: {
  main: { Public: { types: {}, values: {
    answer: { Public: { ExpressionBody: { inputTypes: {}, outputType: int, body: { Literal: { IntegerLiteral: 42 } } } } },
    echo: { Public: { ExpressionBody: { inputTypes: { input: list }, outputType: list, body: { Variable: 'input' } } } },
  } } },
} } } } });
await writeFile(join(evidence, 'lifecycle-model.json'), model + '\n');
const bulk = JSON.stringify([{ type: 'list', items: Array.from({ length: 15000 }, () => ({ type: 'int', value: '7' })) }]);
const submission = (descriptor: NativeDescriptor, entry: 'answer' | 'echo') => ({ contractVersion: '0.2.0-draft.1', model,
  entry: `lifecycle:main#${entry}`, runtime: 'scheme', providerId: (descriptor.offer as { providerId: string }).providerId,
  inputs: { format: 'json', source: entry === 'answer' ? '[]' : bulk } });

async function normalQuit(pid: number) {
  // AppKit documents this API as "Attempts to quit the receiver normally".
  // A PID target avoids quitting another instance with the same bundle ID.
  const result = await run('osascript', ['-l', 'JavaScript', '-e',
    `ObjC.import('AppKit'); var app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(${pid}); if (!app || !app.terminate) throw new Error('Normal quit request was refused'); 'normal-quit-request-sent';`]);
  assert.match(result.stdout, /normal-quit-request-sent/);
}

let app: ChildProcess | undefined, browser: Browser | undefined;
const workers: ProcessRow[] = [], phases: Phase[] = [];
let qualified = false, failure: string | null = null;
let appExit: { code: number | null; signal: NodeJS.Signals | null } | undefined;
let profile: string | null = null;
const oldProfiles = new Set((await inventory()).flatMap(row => row.command.match(/--user-data-dir=(\S+)/)?.[1] ?? []));
const reservation = createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
const address = reservation.address(); assert.ok(address && typeof address !== 'string'); const port = address.port;
await new Promise<void>((resolve, reject) => reservation.close(error => error ? reject(error) : resolve()));
const environment: NodeJS.ProcessEnv = { ...process.env, PROTON_HEADLESS: '1', PROTON_REMOTE_DEBUGGING_PORT: String(port) };
delete environment.PROTON_FRONTEND_URL; delete environment.MORPHIR_WORKBENCH_LAUNCH_URL;
let output = '';
try {
  app = spawn(executable, [], { env: environment, stdio: ['ignore', 'pipe', 'pipe'] });
  assert.ok(app.pid); const parent = app.pid;
  const exited = new Promise<void>(resolve => app!.once('exit', (code, signal) => { appExit = { code, signal }; resolve(); }));
  app.on('error', error => { failure = error.message; });
  for (const stream of [app.stdout, app.stderr]) stream?.on('data', chunk => { output = (output + String(chunk)).slice(-131072); });
  await until(async () => {
    assert.equal(appExit, undefined, 'The owned package exited before CDP startup');
    const response = await fetch(`http://127.0.0.1:${port}/json/version`).catch(() => null);
    return response?.ok ? true : null;
  }, 'owned package CDP startup', 30000);
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
  const page = browser.contexts()[0]?.pages().find(page => page.url().includes('proton.localhost'));
  assert.ok(page, 'The owned package serves its bundled main page');
  page.setDefaultTimeout(15000);
  const ready = () => page.waitForFunction(() => typeof globalThis.morphirWorkbenchExecutions === 'function' && typeof window.__MoonBit__?.core?.invokeOp === 'function');
  await ready();
  const reload = async () => { await page.reload(); await ready(); };
  const children = descendants(await inventory(), parent);
  profile = children.flatMap(row => row.command.match(/--user-data-dir=(\S+)/)?.[1] ?? [])[0] ?? null;
  assert.ok(profile, 'Actual CEF child arguments identify the native-owned temporary browser profile');
  assert.ok(!oldProfiles.has(profile), 'The package uses a different profile from every previously running CEF instance');

  async function open() {
    const descriptor = value(await native<NativeDescriptor>(page!, 'session.open', null));
    assert.equal(descriptor.contractVersion, '0.2.0-draft.2');
    assert.ok(descriptor.operations.includes('executions')); return descriptor;
  }
  async function answer(descriptor: NativeDescriptor) {
    const accepted = value(await native<SchemeSubmission>(page!, 'execution.submit', descriptor.sessionId, submission(descriptor, 'answer')));
    const receipt = await until(async () => {
      const current = value(await native<Receipt>(page!, 'execution.query', descriptor.sessionId, identityBody(accepted.identity)));
      return current.state === 'terminal' ? current : null;
    }, 'actual native typed baseline evaluation');
    assert.deepEqual(receipt.outcomes?.calls[0]?.outcome, { status: 'returned', value: { type: 'int', value: '42' } });
    value(await native(page!, 'execution.release', descriptor.sessionId, identityBody(accepted.identity)));
    assert.equal((await inventory()).filter(row => isWorker(row, parent)).length, 0, 'Terminal baseline has no live owned native worker');
    return receipt;
  }
  async function held(descriptor: NativeDescriptor): Promise<HeldExecution> {
    assert.equal((await inventory()).filter(row => isWorker(row, parent)).length, 0);
    let searching = true;
    const observed = until(async () => {
      if (!searching) throw new Error('Worker observation cancelled');
      const row = (await inventory()).find(row => isWorker(row, parent));
      if (!row) return null;
      // The fresh OS row verifies the exact executable and direct parent before
      // signaling. The following read verifies its birth and stopped state.
      process.kill(row.pid, 'SIGSTOP'); workers.push(row);
      return row;
    }, 'a verified native owner-spawned worker', 10000);
    observed.catch(() => {});
    try {
      const accepted = value(await native<SchemeSubmission>(page!, 'execution.submit', descriptor.sessionId, submission(descriptor, 'echo')));
      assert.equal(accepted.plan.admission.policy, 'strict');
      assert.deepEqual(accepted.plan.identity, accepted.identity);
      const worker = await observed;
      await until(async () => (await inventory()).find(row => sameProcess(row, worker) && row.state.includes('T')) ?? null, 'native worker stopped by the acceptance observer');
      const running = value(await native<Receipt>(page!, 'execution.query', descriptor.sessionId, identityBody(accepted.identity)));
      assert.equal(running.state, 'running', 'The stopped real worker has no published terminal receipt');
      assert.equal(running.outcomes, null); return { accepted, worker, running };
    } catch (error) { searching = false; await observed.catch(() => {}); throw error; }
  }

  let descriptor = await open();
  const baseline = await answer(descriptor);
  for (const lifecycle of ['reload', 'session.close'] as const) {
    const retained = await held(descriptor), old = descriptor;
    let replacement: NativeDescriptor | undefined;
    if (lifecycle === 'reload') { await reload(); replacement = await open(); }
    else value(await native(page, 'session.close', descriptor.sessionId));
    assert.ok(!sameProcess((await inventory()).find(row => row.pid === retained.worker.pid), retained.worker),
      'Native worker exit is already confirmed when the lifecycle boundary returns');
    phases.push({ lifecycle, worker: retained.worker, identity: retained.accepted.identity, running: retained.running,
      workerRemoved: true, confirmedAt: lifecycle === 'reload' ? 'replacement-session-reply' : 'session-close-reply' });
    const denied = await native(page, 'session.check', old.sessionId);
    assert.ok(!denied.ok && denied.error.code === 'unauthorized', 'Old session authority is revoked');
    if (lifecycle === 'session.close') await reload();
    descriptor = replacement ?? await open(); assert.notEqual(descriptor.sessionId, old.sessionId);
    const oldQuery = await native(page, 'execution.query', descriptor.sessionId, identityBody(retained.accepted.identity));
    assert.ok(!oldQuery.ok, 'A replacement session cannot observe an execution retained by the old owner');
    await answer(descriptor);
  }
  const retained = await held(descriptor);
  const beforeQuit = descendants(await inventory(), parent);
  await normalQuit(parent);
  await until(async () => appExit === undefined ? null : appExit, 'normal macOS application quit');
  await exited;
  assert.deepEqual(appExit, { code: 0, signal: null }, 'Normal quit exits cleanly without any Unix signal');
  assert.ok(!sameProcess((await inventory()).find(row => row.pid === retained.worker.pid), retained.worker),
    'The actual native worker is already removed at normal application exit');
  for (const child of beforeQuit) await removed(child);
  phases.push({ lifecycle: 'normal-application-quit', worker: retained.worker, identity: retained.accepted.identity,
    running: retained.running, workerRemoved: true, confirmedAt: 'normal-application-exit' });
  await writeFile(join(evidence, 'baseline-receipt.json'), JSON.stringify(baseline, null, 2) + '\n');
  qualified = true;
} catch (error) {
  failure = error instanceof Error ? error.stack ?? error.message : String(error);
  throw error;
} finally {
  // Failure cleanup never contributes qualification evidence. Resume only a
  // initially verified worker with the same PID and OS birth, then ask this one
  // owned application to quit normally before bounded emergency cleanup.
  for (const worker of workers) {
    const live = (await inventory()).find(row => row.pid === worker.pid);
    if (sameProcess(live, worker) && live!.state.includes('T')) process.kill(worker.pid, 'SIGCONT');
  }
  if (app?.pid && appExit === undefined) {
    await normalQuit(app.pid).catch(() => {});
    await until(async () => appExit === undefined ? null : true, 'cleanup normal quit', 5000).catch(() => {});
    if (appExit === undefined) {
      app.kill('SIGTERM');
      await until(async () => appExit === undefined ? null : true, 'cleanup SIGTERM', 2000).catch(() => {});
      if (appExit === undefined) app.kill('SIGKILL');
    }
  }
  for (const worker of workers) {
    const live = (await inventory()).find(row => row.pid === worker.pid);
    if (sameProcess(live, worker)) process.kill(worker.pid, 'SIGKILL');
  }
  await browser?.close().catch(() => {});
  await writeFile(join(evidence, 'package.log'), output);
  const binary = await readFile(executable);
  await writeFile(join(evidence, 'receipt.json'), JSON.stringify({ qualified, startedAt, completedAt: new Date().toISOString(),
    platform: process.platform, arch: process.arch, package: appPath, executable, binarySha256: createHash('sha256').update(binary).digest('hex'),
    parentPid: app?.pid, cdpPort: port, nativeOwnedTemporaryProfile: profile, phases, appExit,
    normalQuitMechanism: 'AppKit NSRunningApplication.terminate() targeted by owned PID; no signal used for qualification',
    stoppedWorkers: workers, failure,
  }, null, 2) + '\n');
}
console.log(`Packaged native lifecycle acceptance passed: reload, session.close and normal macOS application quit; evidence ${evidence}`);
