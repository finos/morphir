import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createReadStream } from 'node:fs';
import { access, lstat, mkdtemp, open, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer as httpServer } from 'node:http';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { chromium, type Browser, type Page } from 'playwright';
import { supervised } from '../../morphir/build-provider/supervision.mjs';
import type { CoreReply, NativeDescriptor, NativeReply } from '../browser/contracts.ts';
import { fallbackWorkerWorkflow } from './desktop-fallback-workflow.ts';
import { NormalPackageExit, TemporaryProfileOwner, type ProfileCleanup } from './desktop-profile-owner.ts';

// This application acceptance owns its real package fixture through the same
// process-group/Windows Job supervisor qualified by the installed CLI tests.
// Target selection, builds and the matrix gate remain MoonBit task commands.
type Target = 'linux-x64' | 'windows-x64';
type EmptyDescriptor = Pick<NativeDescriptor, 'profile' | 'contractVersion' | 'sessionId' | 'operations'>;
const target = process.argv[2];
assert.ok(target === 'linux-x64' || target === 'windows-x64', 'Select linux-x64 or windows-x64');
assert.equal(`${process.platform}:${process.arch}`, target === 'linux-x64' ? 'linux:x64' : 'win32:x64', 'Use the actual selected host');
const evidence = resolve(process.argv[3] ?? `.dev/packaged-targets/${target}`);
const build: unknown = JSON.parse(await readFile(join(evidence, 'build.json'), 'utf8'));
assert.ok(build && typeof build === 'object' && 'target' in build && build.target === target && 'status' in build && build.status === 'built');
await assert.rejects(access(join(evidence, 'acceptance.json')), 'Never replace a previous acceptance receipt');
const packageRoot = await realpath(join(evidence, 'package'));
const entry = target === 'linux-x64' ? join(packageRoot, 'morphir-workbench-0.1.0-x86_64.AppImage')
  : join(packageRoot, 'morphir-workbench', 'morphir-workbench.exe');
assert.equal((await lstat(entry)).isFile(), true);
const executable = await open(entry, 'r');
const header = Buffer.alloc(128);
try { assert.equal((await executable.read(header, 0, header.length, 0)).bytesRead, header.length); }
finally { await executable.close(); }
if (target === 'linux-x64') {
  assert.equal(header.subarray(0, 4).toString('hex'), '7f454c46');
  assert.equal(header.readUInt16LE(18), 62, 'The AppImage is x86-64');
  assert.equal(header.subarray(8, 11).toString('hex'), '414902', 'Launch the type-2 AppImage entry');
} else {
  assert.equal(header.subarray(0, 2).toString(), 'MZ');
  const helper = await readFile(join(packageRoot, 'morphir-workbench', 'cef_process.exe'));
  assert.equal(helper.readUInt16LE(helper.readUInt32LE(0x3c) + 92), 2, 'The real packaged CEF helper uses the Windows GUI subsystem');
}

async function digest(path: string) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
async function inventory(root: string, prefix = ''): Promise<{ path: string; sha256: string }[]> {
  const result: { path: string; sha256: string }[] = [];
  for (const name of (await readdir(join(root, prefix))).sort()) {
    const path = prefix ? `${prefix}/${name}` : name;
    const stat = await lstat(join(root, path));
    assert.equal(stat.isSymbolicLink(), false, 'Portable package inventory contains no links');
    if (stat.isDirectory()) result.push(...await inventory(root, path));
    else { assert.ok(stat.isFile()); result.push({ path, sha256: await digest(join(root, path)) }); }
  }
  return result;
}
const files = await inventory(packageRoot);
const reservation = createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
const address = reservation.address(); assert.ok(address && typeof address !== 'string');
const port = address.port;
await new Promise<void>(resolve => reservation.close(() => resolve()));
const scratch = await mkdtemp(join(tmpdir(), 'morphir-packaged-fallback-'));
const profileOwner = await TemporaryProfileOwner.create(scratch);
const profileRoot = profileOwner.path;
const cancelFile = join(scratch, 'cancel');
const env: NodeJS.ProcessEnv = { ...process.env };
for (const key of Object.keys(env)) if (/^(PROTON_|CEF_|MORPHIR_|DYLD_)/i.test(key) || ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'NODE_OPTIONS'].includes(key)) delete env[key];
Object.assign(env, { PROTON_HEADLESS: '1', PROTON_REMOTE_DEBUGGING_PORT: String(port), TMPDIR: profileRoot, TEMP: profileRoot, TMP: profileRoot });
if (target === 'windows-x64') env.ANGLE_DEFAULT_PLATFORM = 'swiftshader';
const args = target === 'linux-x64' ? ['--appimage-extract-and-run'] : [];
let quiescent = false, forcedCleanup = false;
const exit = supervised(entry, args, { cwd: packageRoot, env, timeout: 600000, cancelFile }).then(result => {
  quiescent = true;
  return { kind: 'exit' as const, result };
}, (error: unknown) => {
  const message = String(error);
  quiescent = !message.includes('execution.tree_termination_failed');
  return { kind: 'error' as const, message };
});
let exited = false; void exit.then(() => { exited = true; });
let browser: Browser | undefined;
const checks: string[] = [], errors: string[] = [];
let workersStarted = 0, workersClosed = 0;
let profiles: string[] = [];
type AcceptanceStage = 'cdp-startup' | 'bundled-page' | 'workflows' | 'worker-exit' | 'entry-exit' | 'profile-cleanup';
let stage: AcceptanceStage = 'cdp-startup';
const until = async (condition: () => Promise<boolean>, milliseconds = 30000) => {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) { if (await condition()) return; await pause(50); }
  throw new Error(`Packaged acceptance condition timed out: ${stage}`);
};
// Inspect only this launch's owned temporary root. Bound diagnostics and never
// follow links, read profile contents, remove files or change the acceptance gate.
async function remainingProfileEntries() {
  const entries: { path: string; kind: 'directory' | 'file' | 'link' | 'other'; mode: number; bytes: number }[] = [];
  let truncated = false;
  async function visit(prefix: string, depth: number): Promise<void> {
    for (const name of (await readdir(join(profileRoot, prefix))).sort()) {
      if (entries.length === 256) { truncated = true; return; }
      const path = prefix ? `${prefix}/${name}` : name;
      const stat = await lstat(join(profileRoot, path));
      const kind = stat.isSymbolicLink() ? 'link' : stat.isDirectory() ? 'directory' : stat.isFile() ? 'file' : 'other';
      entries.push({ path, kind, mode: stat.mode, bytes: stat.size });
      if (kind === 'directory') {
        if (depth === 8) truncated = true;
        else await visit(path, depth + 1);
      }
    }
  }
  try { await visit('', 0); return { entries, truncated }; }
  catch (error) { return { entries, truncated, error: String(error) }; }
}
async function native<T>(page: Page, operation: string, sessionId: string | null = null, payload?: unknown): Promise<NativeReply<T>> {
  return page.evaluate(async ({ operation, sessionId, payload }) => {
    const source = JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation,
      ...(sessionId === null ? {} : { sessionId }), ...(payload === undefined ? {} : { payload }) });
    const raw = await window.__MoonBit__!.core!.invokeOp!('app:workbench_native', source);
    const checked: CoreReply<NativeReply<T>> = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({
      op: 'native-policy-response', source: raw, operation, sessionId,
    })));
    if (!checked.ok) throw new Error(`Native reply failed the production codec: ${checked.code}`);
    return checked.value;
  }, { operation, sessionId, payload });
}
function value<T>(reply: NativeReply<T>): T { assert.ok(reply.ok, JSON.stringify(reply)); return reply.value; }
function denied(reply: NativeReply<unknown>, code: string) { assert.ok(!reply.ok); assert.equal(reply.error.code, code, JSON.stringify(reply)); assert.equal(reply.error.effect, 'none'); }
function empty(descriptor: EmptyDescriptor) {
  assert.deepEqual(Object.keys(descriptor).sort(), ['contractVersion', 'operations', 'profile', 'sessionId']);
  assert.equal(descriptor.profile, 'morphir/workbench/native'); assert.equal(descriptor.contractVersion, '0.2.0-draft.2');
  assert.deepEqual(descriptor.operations, []); assert.ok(descriptor.sessionId.length > 0);
}
let failure: string | null = null;
let profileCleanup: ProfileCleanup | undefined;
try {
  await until(async () => {
    if (exited) throw new Error(`Package exited before CDP startup: ${JSON.stringify(await exit)}`);
    return (await fetch(`http://127.0.0.1:${port}/json/version`).catch(() => null))?.ok === true;
  });
  const connection = { timeout: 30000, noDefaults: true };
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, connection);
  stage = 'bundled-page';
  let discoveredPage: Page | undefined;
  await until(async () => {
    if (exited) throw new Error(`Package exited before its bundled page appeared: ${JSON.stringify(await exit)}`);
    discoveredPage = browser!.contexts()[0]?.pages().find(page => new URL(page.url()).hostname === 'proton.localhost');
    return discoveredPage !== undefined;
  });
  const page = discoveredPage;
  stage = 'workflows';
  assert.ok(page, 'The actual package serves its bundled main page'); page.setDefaultTimeout(20000);
  page.on('pageerror', error => errors.push(error.message));
  const resources: string[] = [];
  page.on('request', request => resources.push(request.url()));
  page.on('worker', worker => { workersStarted++; worker.once('close', () => { workersClosed++; }); });
  await page.reload(); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const original = page.url();
  profiles = await profileOwner.observe();
  const opened = value(await native<EmptyDescriptor>(page, 'session.open')); empty(opened);
  assert.deepEqual(value(await native(page, 'session.check', opened.sessionId)), opened);
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Desktop local');
  denied(await native(page, 'workspace.choose', opened.sessionId), 'unavailable');
  const submission = { contractVersion: '0.2.0-draft.1', model: '{}', entry: 'probe:main#answer', inputs: { format: 'json', source: '[]' } };
  denied(await native(page, 'execution.submit', opened.sessionId, submission), 'invalid_request');
  denied(await native(page, 'execution.submit', opened.sessionId, { ...submission, runtime: 'scheme', providerId: 'moonbit-scheme' }), 'unavailable');
  assert.deepEqual(value(await native(page, 'session.check', opened.sessionId)), opened, 'Unavailable effects preserve existing page authority');
  checks.push('empty-descriptor-and-unavailable-native-effects');
  checks.push(await fallbackWorkerWorkflow(page, 'native-fallback'));
  assert.ok(resources.every(url => { const value = new URL(url); return ['blob:', 'data:'].includes(value.protocol) || value.hostname === 'proton.localhost'; }), 'Bundled workflows must not depend on a development or external asset origin');
  await page.reload(); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const replacement = value(await native<EmptyDescriptor>(page, 'session.open')); empty(replacement);
  assert.notEqual(replacement.sessionId, opened.sessionId);
  denied(await native(page, 'session.check', opened.sessionId), 'unauthorized');
  value(await native(page, 'session.close', replacement.sessionId));
  denied(await native(page, 'session.check', replacement.sessionId), 'unauthorized');
  checks.push('reload-and-close-revoke-old-session');
  const hostile = httpServer((_, response) => { response.writeHead(200, { 'Content-Type': 'text/html' }); response.end('<!doctype html><title>Untrusted origin</title>'); });
  try {
    hostile.listen(0, '127.0.0.1'); await once(hostile, 'listening');
    const bound = hostile.address(); assert.ok(bound && typeof bound !== 'string');
    await page.goto(`http://127.0.0.1:${bound.port}`);
    const access = await page.evaluate(async () => {
      if (typeof window.__MoonBit__?.core?.invokeOp !== 'function') return 'absent';
      return Promise.race([Promise.resolve(window.__MoonBit__.core.invokeOp('app:workbench_native', JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation: 'session.open' }))).then(() => 'allowed', () => 'rejected'), new Promise(resolve => setTimeout(() => resolve('timeout'), 5000))]);
    });
    assert.ok(access === 'absent' || access === 'rejected', `Hostile origin must not obtain authority: ${access}`);
  } finally { hostile.closeAllConnections(); await new Promise<void>(resolve => hostile.close(() => resolve())); }
  checks.push('hostile-origin-denied');
  const standalone = new URL(original); standalone.search = '?mode=standalone';
  await page.goto(standalone.href); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Browser local');
  checks.push(await fallbackWorkerWorkflow(page, 'standalone'));
  stage = 'worker-exit';
  await until(async () => workersStarted >= 8 && workersStarted === workersClosed && page.workers().length === 0, 10000);
  assert.deepEqual(errors, []); checks.push('actual-browser-workers-exit');
  await page.screenshot({ path: join(evidence, 'fallback.png'), fullPage: true });
  // This is the real CEF target/window close path. A forced supervisor cleanup
  // below cannot satisfy the normal entry-exit assertion.
  await page.close({ runBeforeUnload: true });
  stage = 'entry-exit';
  await until(async () => exited, 15000);
  const result = await exit;
  assert.equal(result.kind, 'exit', JSON.stringify(result));
  assert.deepEqual({ code: result.result.code, signal: result.result.signal }, { code: 0, signal: null });
  stage = 'profile-cleanup';
  profileCleanup = await profileOwner.cleanupAfterExit(NormalPackageExit.checked(result.result, quiescent));
  checks.push('real-window-close-and-profile-cleanup');
  await writeFile(join(evidence, 'package.log'), result.result.stdout + result.result.stderr);
  await writeFile(join(evidence, 'acceptance.json'), JSON.stringify({ profile: 'morphir/workbench/packaged-fallback', formatVersion: 1,
    target: target as Target, build, passed: true, checks, entry: basename(entry), files, workersStarted, workersClosed,
    profiles, profileRemoved: true, profileCleanup, quiescent, entryExit: { code: 0, signal: null }, forcedCleanup: false,
    helperCleanup: 'existing owned-process-group or Windows Job supervisor confirmed quiescence; remaining helpers may be reclaimed',
    scope: 'actual packaged CEF, empty native descriptor and browser-worker fallback; excludes native workers, OS pickers, Save dialogs and installers' }, null, 2) + '\n');
  console.log(`Actual ${target} packaged fallback passed: ${checks.length} checks, ${workersStarted} real workers closed.`);
} catch (error) {
  failure = String(error);
  const page = browser?.contexts()[0]?.pages().find(page => new URL(page.url()).hostname === 'proton.localhost');
  await page?.screenshot({ path: join(evidence, 'fallback-failure.png'), fullPage: true }).catch(() => {});
  throw error;
} finally {
  if (!exited) { forcedCleanup = true; await writeFile(cancelFile, 'cancel\n'); }
  const result = await exit;
  await browser?.close().catch(() => {});
  if (failure !== null) await writeFile(join(evidence, 'acceptance-failure.json'), JSON.stringify({ passed: false, target, build, failure, stage, checks, errors, workersStarted, workersClosed, result, forcedCleanup, quiescent, scratch, remainingProfile: await remainingProfileEntries() }, null, 2) + '\n');
  // Preserve nonprofile siblings, including AppImage extraction state. Neither
  // a refusal nor profile-only success authorizes their recursive deletion.
  if (quiescent && failure === null && profileCleanup?.temporaryRetention.kind === 'empty') {
    await rm(scratch, { recursive: true, force: true });
  }
}
