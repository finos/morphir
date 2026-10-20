import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Worker } from 'node:worker_threads';
import type { AddressInfo } from 'node:net';
import { createWorkbenchServer } from '../../morphir-workbench/scripts/server.ts';
import { createExecutionProvider } from '../../morphir-workbench/scripts/execution-provider.ts';
import type { ExecutionGateway, ExecutionProvider, Identity, ProviderWorker } from '../../morphir-workbench/scripts/execution-contracts.ts';
import { headlessEnvironment } from './headless-environment.ts';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
const portable = target === 'wasm' || target === 'wasm-gc';
const rust = process.env.MORPHIR_WORKBENCH_LIVE_HOST;
if (!portable && process.platform !== 'win32') assert.ok(rust, 'Select a qualified actual Rust host with MORPHIR_WORKBENCH_LIVE_HOST');
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-connected');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
const launcher = process.env.MORPHIR_HEADLESS_LAUNCHER ?? join(repo, 'apps/morphir/bin/morphir.js');
const helper = process.env.MORPHIR_CONNECTED_HELPER ?? join(repo, 'apps/morphir/build-provider/connected.mjs');
const artifacts = resolve(repo, process.env.MORPHIR_CONNECTED_PROVIDER_BUILD ?? '.dev/build-connected');
const bridge = pathToFileURL(join(artifacts, 'js/release/build/finos/morphir-workbench/execution-host/execution-host.js'));
const workerModule = pathToFileURL(join(artifacts, 'js/release/build/finos/morphir-workbench/worker/worker.js'));
const corpus = JSON.parse(readFileSync(join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.12/cases.json'), 'utf8'));
const fixed = corpus.cases[0];
assert.equal(fixed.id, 'selected-permissive-unused-hole-int42');
const request = { source: fixed.input.model, entry: fixed.input.calls[0].entry,
  arguments: JSON.parse(fixed.input.calls[0].inputs.source), admission: fixed.input.admission, executionMode: 'capability' };
const expectedOutcomes = { ...fixed.expected.value.outcomes, calls: fixed.expected.value.outcomes.calls.map((call: object) => ({ ...call, id: 'workbench' })) };
const program = target === 'native' ? binary : process.execPath;
const runner = process.env.MORPHIR_HEADLESS_WASM_RUNNER ?? join(repo, 'pkgs/morphir-host/runners/wasm.mjs');
const prefix = target === 'native' ? [] : target === 'js' ? [launcher] : [runner, binary];
type Scenario = 'normal' | 'lost-submit' | 'lost-query' | 'lost-release' | 'cancel' | 'cancel-unknown' | 'late-completion' | 'terminal-query-lost' | 'host-exit' | 'timeout' |
  'connect-pre-cancel' | 'connect-pending-cancel' | 'connect-selection-cancel' | 'connect-pending-sigint' | 'connect-pending-timeout' | 'connect-replaced-cancel';

function launch(args: string[], cwd: string, input?: string, selectedHelper = helper) {
  const child = spawn(program, [...prefix, ...args, '--provider', 'workbench-http', '--connected-helper', selectedHelper, '--json'], {
    cwd, env: headlessEnvironment(join(cwd, 'cli-environment'), {
      TMPDIR: cwd, TMP: cwd, TEMP: cwd, MORPHIR_CONNECTED_HELPER: helper,
    }), stdio: ['pipe', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '';
  child.stdout.setEncoding('utf8').on('data', value => { stdout += value; });
  child.stderr.setEncoding('utf8').on('data', value => { stderr += value; });
  child.stdin.on('error', error => { if ((error as NodeJS.ErrnoException).code !== 'EPIPE') throw error; });
  if (input !== undefined) child.stdin.end(input); else child.stdin.end();
  const done = new Promise<{ code: number | null; signal: string | null; stdout: string; stderr: string }>((resolve, reject) => {
    const timer = setTimeout(() => child.kill('SIGKILL'), 20000);
    child.once('error', reject);
    child.once('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, stdout, stderr }); });
  });
  return { child, done };
}
function delayedWorker(env: NodeJS.ProcessEnv): ProviderWorker {
  const worker = new Worker(new URL('../../morphir-workbench/scripts/execution-worker.ts', import.meta.url), { workerData: { module: workerModule.href }, env });
  let timer: ReturnType<typeof setTimeout> | undefined;
  worker.once('exit', () => { if (timer) clearTimeout(timer); });
  return {
    on: worker.on.bind(worker), once: worker.once.bind(worker), terminate: worker.terminate.bind(worker),
    postMessage(message) { timer = setTimeout(() => worker.postMessage(message), 1000); },
  };
}
async function scenario(name: Scenario) {
  const root = mkdtempSync(join(tmpdir(), 'morphir-connected-cli-'));
  const workspace = join(root, 'workspace');
  mkdirSync(workspace);
  writeFileSync(join(workspace, 'morphir.toml'), '[project]\nname="connected/test"\nversion="1.0.0"\nsource_directory="src"\n');
  let host: ChildProcess | undefined;
  let server: ReturnType<typeof createWorkbenchServer> | undefined;
  let provider: ExecutionProvider | undefined;
  let running: ChildProcess | undefined;
  const heldQueries = new Set<() => void>();
  const releaseQuery = () => { for (const release of heldQueries) release(); heldQueries.clear(); };
  let queryStarted: () => void = () => {};
  const querying = new Promise<void>(resolve => { queryStarted = resolve; });
  let acceptedIdentity: Identity | undefined;
  let authenticatedSession: string | undefined;
  let resolveAccepted: () => void = () => {};
  const accepted = new Promise<void>(resolve => { resolveAccepted = resolve; });
  let resolveAuthenticating: () => void = () => {};
  const authenticating = new Promise<void>(resolve => { resolveAuthenticating = resolve; });
  let launches = 0;
  const counts = { submit: 0, query: 0, cancel: 0, release: 0, session: 0 };
  try {
    host = spawn(rust!, ['ui', workspace, '--no-open', '--no-banner'], {
      cwd: workspace, env: headlessEnvironment(join(root, 'host-environment'), {RUST_LOG: 'warn'}),
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    const launchURL = await new Promise<URL>((resolve, reject) => {
      let buffer = '';
      const timer = setTimeout(() => reject(new Error('Qualified Rust host startup deadline')), 15000);
      host!.once('error', reject);
      host!.once('exit', () => reject(new Error('Qualified Rust host exited before authentication')));
      host!.stderr!.on('data', data => {
        buffer = (buffer + data).slice(-16384);
        const value = buffer.match(/Morphir UI: (http:\/\/127\.0\.0\.1:\d+\/launch[^\s]+)/)?.[1];
        if (value) { clearTimeout(timer); resolve(new URL(value)); }
      });
    });
    const workerEnvironment = headlessEnvironment(join(root, 'worker-environment'));
    provider = await createExecutionProvider({ mapping: 'capability-checks', bridgeUrl: bridge, workerUrl: workerModule,
      workerFactory: ['cancel', 'cancel-unknown', 'timeout'].includes(name)
        ? () => delayedWorker(workerEnvironment)
        : () => new Worker(new URL('../../morphir-workbench/scripts/execution-worker.ts', import.meta.url), {
          workerData: {module: workerModule.href}, env: workerEnvironment, resourceLimits: {maxOldGenerationSizeMb: 128},
        }),
    });
    const real = provider;
    const gateway: ExecutionGateway = {
      decode: real.decode.bind(real),
      async session(sessionId) { counts.session++; authenticatedSession = sessionId; return real.session(sessionId); },
      async command(op, body, sessionId) {
        counts[op]++;
        if (op === 'query' && (name === 'cancel-unknown' || name === 'late-completion' || name === 'terminal-query-lost')) {
          queryStarted();
          await new Promise<void>(resolve => { heldQueries.add(resolve); });
        }
        const value = await real.command(op, body, sessionId);
        if (op === 'submit') {
          acceptedIdentity = (value as { identity: Identity }).identity;
          resolveAccepted();
        }
        if (op === 'cancel' && (name === 'late-completion' || name === 'terminal-query-lost')) releaseQuery();
        return value;
      },
      close: real.close.bind(real),
    };
    server = createWorkbenchServer({ host: launchURL.origin, executions: gateway, root: pathToFileURL(root + '/no-ui-assets/') });
    // Drop the real HTTP reply only after the authenticated gateway has applied
    // its effect. No fabricated result or substitute lifecycle reducer is used.
    const drop = name === 'lost-submit' ? 'submit' : name === 'lost-query' ? 'query' : name === 'lost-release' ? 'release' : name === 'cancel-unknown' ? 'cancel' : name === 'terminal-query-lost' ? 'query' : null;
    let dropped = false;
    server.prependListener('request', (incoming, response) => {
      if (incoming.url?.startsWith('/launch?')) {
        launches++;
        if (name.startsWith('connect-') && name !== 'connect-pre-cancel' && name !== 'connect-selection-cancel' && launches === 1) {
          // Hold the actual host reply after the one-use token was consumed.
          // Cancellation cannot establish that this remote effect was undone.
          response.end = () => { resolveAuthenticating(); return response; };
        }
      }
      if (name === 'connect-selection-cancel' && incoming.url === '/api/workbench/session') {
        response.end = () => { resolveAuthenticating(); return response; };
      }
      if (!dropped && drop && incoming.url === `/api/workbench/${drop}`) {
        dropped = true;
        response.end = () => { if (name === 'terminal-query-lost') setTimeout(() => response.destroy(), 50); else response.destroy(); return response; };
      }
    });
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const secret = launchURL.searchParams.get('token')!;
    const launchFile = join(root, 'launch.txt'), connection = join(root, 'connection.json'), input = join(root, 'request.json');
    writeFileSync(launchFile, origin + launchURL.pathname + launchURL.search, { mode: 0o600 });
    writeFileSync(input, JSON.stringify(request));
    if (name.startsWith('connect-')) {
      const cancelFile = join(root, 'cancel');
      if (name === 'connect-pre-cancel') writeFileSync(cancelFile, 'cancel');
      const invocation = launch(['connected', 'connect', launchFile, '--connection', connection,
        '--cancel-file', cancelFile, '--timeout', name === 'connect-pending-timeout' ? '500' : '5000'], root);
      running = invocation.child;
      if (name !== 'connect-pre-cancel') {
        await Promise.race([authenticating, invocation.done.then(result => {
          throw new Error('Connect exited before the host authenticated: ' + result.stdout + result.stderr);
        })]);
        if (name === 'connect-replaced-cancel') {
          renameSync(connection, join(root, 'owned-connection'));
          writeFileSync(connection, 'another owner', { mode: 0o600 });
        }
        if (name === 'connect-pending-sigint') invocation.child.kill('SIGINT');
        else if (name !== 'connect-pending-timeout') writeFileSync(cancelFile, 'cancel');
      }
      const cancelledAt = performance.now();
      const result = await invocation.done;
      assert.equal(result.signal, null, result.stdout + result.stderr);
      assert.equal(result.code, name === 'connect-pending-timeout' ? 1 : 130, result.stdout + result.stderr);
      assert.ok(performance.now() - cancelledAt < 2000, 'Cancellation must not wait for the authentication timeout');
      if (name === 'connect-replaced-cancel') {
        assert.equal(readFileSync(connection, 'utf8'), 'another owner', 'Cleanup preserves a replacement carrier');
        assert.equal(readFileSync(join(root, 'owned-connection'), 'utf8'), '', 'Cancelled connection never writes credentials through its reserved descriptor');
      } else assert.equal(existsSync(connection), false, 'Cancelled connection does not publish credentials');
      assert.deepEqual(readdirSync(root).filter(name => name.startsWith('morphir-toolchain-')), [], 'Owned helper scratch is removed');
      assert.equal(counts.session, name === 'connect-selection-cancel' ? 1 : 0, 'Cancellation never retries capability selection');
      assert.ok(!result.stdout.includes(secret) && !result.stderr.includes(secret));
      if (name === 'connect-pre-cancel') {
        assert.equal(launches, 0, 'Pre-cancellation must not start authentication');
        unlinkSync(cancelFile);
        const retry = await launch(['connected', 'connect', launchFile, '--connection', connection], root).done;
        assert.equal(retry.code, 0, 'Pre-cancellation preserves the unused launch token: ' + retry.stdout);
      } else {
        assert.equal(launches, 1, 'An interrupted authentication is never retried');
        assert.equal(JSON.parse(result.stdout).error, name === 'connect-pending-timeout' ? 'connected.timeout_before_submission' : 'connected.interrupted_before_submission');
        assert.equal((await fetch(origin + launchURL.pathname + launchURL.search, { redirect: 'manual' })).status, 401,
          'Aborting an in-flight authentication does not reverse remote token consumption');
      }
      assert.equal(host.exitCode, null, 'Cancellation does not terminate the remote host');
      console.log(`${target} authenticated connected ${name}: passed`);
      return;
    }
    if (name === 'normal') {
      writeFileSync(connection, 'reserved', { mode: 0o600 });
      const collision = await launch(['connected', 'connect', launchFile, '--connection', connection], root).done;
      assert.equal(collision.code, 2, 'Reserve destination before consuming one-use token');
      unlinkSync(connection);
    }
    const setup = await launch(['connected', 'connect', launchFile, '--connection', connection], root).done;
    assert.equal(setup.signal, null); assert.equal(setup.code, 0, setup.stdout + setup.stderr);
    const credential = JSON.parse(readFileSync(connection, 'utf8'));
    assert.equal(statSync(connection).mode & 0o077, 0);
    assert.equal((await fetch(origin + launchURL.pathname + launchURL.search, { redirect: 'manual' })).status, 401);
    assert.ok(!setup.stdout.includes(secret) && !setup.stderr.includes(secret));
    if (name === 'normal') {
      chmodSync(connection, 0o644);
      const denied = await launch(['connected', 'run', input, '--connection', connection], root).done;
      assert.equal(denied.code, 2); assert.equal(counts.submit, 0);
      chmodSync(connection, 0o600);
      for (const [changed, expected] of [
        [{ ...credential, sessionId: 'another-session' }, 'connected.session_changed'],
        [{ ...credential, cookie: credential.cookie.split('=')[0] + '=' + 'A'.repeat(43) }, 'connected.authentication_failed'],
        [{ ...credential, descriptor: { ...credential.descriptor, offer: { ...credential.descriptor.offer, hostId: 'another-host' } } }, 'connected.offer_changed'],
      ] as const) {
        writeFileSync(connection, JSON.stringify(changed));
        const denied = await launch(['connected', 'run', input, '--connection', connection], root).done;
        assert.equal(denied.code, 2); assert.equal(JSON.parse(denied.stdout).error, expected); assert.equal(counts.submit, 0);
      }
      writeFileSync(connection, JSON.stringify(credential));
      if (target === 'native') {
        const broken = join(root, 'broken-helper.mjs');
        for (const source of ['process.exit(7);', 'console.log("{");', 'console.log("x".repeat(3145729));']) {
          writeFileSync(broken, source);
          const lost = await launch(['connected', 'run', input, '--connection', connection], root, undefined, broken).done;
          assert.equal(lost.code, 1);
          const report = JSON.parse(lost.stdout);
          assert.equal(report.observation, 'helper-lost'); assert.equal(report.result, null); assert.equal(report.release, 'unknown');
          assert.equal(counts.submit, 0);
        }
      }
    }
    const args = ['connected', 'run', name === 'normal' ? '-' : input, '--connection', connection, '--timeout', name === 'timeout' ? '100' : name === 'cancel-unknown' ? '600' : '5000'];
    if (name === 'normal') {
      for (const source of ['', ' '.repeat(1048577)]) {
        const denied = await launch(['connected', 'run', '-', '--connection', connection], root, source).done;
        assert.equal(denied.code, 2); assert.equal(counts.submit, 0);
      }
    }
    const invocation = launch(args, root, name === 'normal' ? JSON.stringify(request) : undefined); running = invocation.child;
    if (['cancel', 'cancel-unknown', 'late-completion', 'terminal-query-lost', 'host-exit'].includes(name)) {
      await accepted;
      if (name === 'late-completion' || name === 'cancel-unknown' || name === 'terminal-query-lost') await querying;
      if (name === 'late-completion' || name === 'terminal-query-lost') {
        for (let index = 0; index < 100; index++) {
          const receipt = await real.command('query', JSON.stringify({ contractVersion: '0.2.0-draft.1', identity: acceptedIdentity }), authenticatedSession!);
          if (receipt.state === 'terminal') break;
          await new Promise(resolve => setTimeout(resolve, 10));
        }
      }
      if (name === 'host-exit') { host.kill('SIGINT'); await once(host, 'exit'); }
      else invocation.child.kill('SIGINT');
    }
    const result = await invocation.done;
    assert.equal(result.signal, null, result.stdout + result.stderr);
    const report = JSON.parse(result.stdout);
    const secrets = [secret, credential.cookie.split('=')[1]];
    for (const value of secrets) assert.ok(![result.stdout, result.stderr, ...invocation.child.spawnargs].join('\n').includes(value), 'Credentials stay out of argv and output');
    assert.equal(counts.submit, 1, 'No lifecycle failure resubmits');
    assert.deepEqual(readdirSync(root).filter(name => name.startsWith('morphir-toolchain-')), [], 'Owned helper configuration scratch is removed');
    if (name === 'lost-submit') {
      assert.equal(result.code, 1); assert.equal(report.observation, 'submission-unknown');
      assert.equal(report.execution, null); assert.equal(report.result, null); assert.equal(counts.query, 0); assert.equal(counts.release, 0);
    } else if (name === 'host-exit') {
      assert.equal(result.code, 1); assert.equal(report.observation, 'observation-stopped');
      assert.equal(report.result, null); assert.equal(report.release, 'not-requested'); assert.equal(counts.release, 0);
    } else if (name === 'cancel-unknown') {
      assert.equal(result.code, 1); assert.equal(report.observation, 'observation-stopped');
      assert.equal(report.result, null); assert.equal(report.cancellation.requested, true); assert.equal(report.cancellation.acknowledged, false);
      assert.equal(report.release, 'not-requested'); assert.equal(counts.cancel, 1);
    } else {
      assert.equal(report.observation, 'terminal', result.stdout + result.stderr);
      assert.equal(report.release, 'confirmed');
      if (name === 'cancel' || name === 'timeout') {
        assert.equal(result.code, name === 'timeout' ? 1 : 130);
        assert.equal(report.result.terminalOutcomes.calls[0].outcome.status, 'cancelled');
        assert.equal(counts.cancel, 1);
      } else {
        assert.equal(result.code, 0); assert.deepEqual(report.result.terminalOutcomes, expectedOutcomes);
      }
      if (name === 'lost-query' || name === 'lost-release' || name === 'terminal-query-lost') assert.equal(report.reconnects, 1);
      await assert.rejects(real.command('query', JSON.stringify({ contractVersion: '0.2.0-draft.1', identity: acceptedIdentity }), authenticatedSession!), /rejected/);
    }
    if (name !== 'host-exit') assert.equal(host.exitCode, null, 'CLI cancellation does not terminate the remote host');
    console.log(`${target} authenticated connected ${name}: passed`);
  } finally {
    releaseQuery();
    if (running && running.exitCode === null && running.signalCode === null) running.kill('SIGKILL');
    await provider?.close();
    if (server) { server.closeAllConnections(); await new Promise(resolve => server!.close(resolve)); }
    if (host && host.exitCode === null && host.signalCode === null) { host.kill('SIGINT'); await once(host, 'exit'); }
    rmSync(root, { recursive: true, force: true });
  }
}
if (portable) {
  const root = mkdtempSync(join(tmpdir(), 'morphir-connected-portable-'));
  try {
    const help = await launch(['connected', 'run', '--help'], root).done;
    assert.equal(help.code, 0); assert.ok(JSON.parse(help.stdout).usage.includes('connected run'));
    const refused = await launch(['connected', 'run', '-', '--connection', 'unused'], root).done;
    assert.equal(refused.signal, null); assert.equal(refused.code, 2);
    assert.equal(JSON.parse(refused.stdout).error, 'connected.runtime_unavailable');
    console.log(`${target} connected help and explicit host-effects refusal: passed`);
  } finally { rmSync(root, { recursive: true, force: true }); }
} else if (process.platform === 'win32') {
  const root = mkdtempSync(join(tmpdir(), 'morphir-connected-refused-'));
  try {
    const launchFile = join(root, 'launch.txt'), connection = join(root, 'connection.json');
    writeFileSync(launchFile, 'http://127.0.0.1:1/launch?token=' + 'A'.repeat(43));
    const result = await launch(['connected', 'connect', launchFile, '--connection', connection], root).done;
    assert.equal(result.signal, null); assert.equal(result.code, 2);
    assert.equal(JSON.parse(result.stdout).error, target === 'native' ? 'connected.runtime_unavailable' : 'connected.private_file_permissions_unavailable');
    assert.ok(!readdirSync(root).includes('connection.json'));
    console.log(`${target} Windows credential effect explicitly unavailable: passed`);
  } finally { rmSync(root, {recursive:true,force:true}); }
} else {
console.log(JSON.stringify({ hostBinary: rust, sha256: createHash('sha256').update(readFileSync(rust!)).digest('hex'), target }));
const scenarios = ['connect-pre-cancel', 'connect-pending-cancel', 'connect-selection-cancel', 'connect-pending-sigint', 'connect-pending-timeout', 'connect-replaced-cancel',
  'normal', 'lost-submit', 'lost-query', 'lost-release', 'cancel', 'cancel-unknown', 'late-completion', 'terminal-query-lost', 'host-exit', 'timeout'] as const;
const selected = process.env.MORPHIR_CONNECTED_SCENARIO;
assert.ok(!selected || scenarios.some(name => name === selected), 'Select a maintained connected scenario');
for (const name of scenarios) if (!selected || name === selected) await scenario(name);

}
