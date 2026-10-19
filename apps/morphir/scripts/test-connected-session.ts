import assert from 'node:assert/strict';
import { once } from 'node:events';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { establishConnection, Refusal } from '../../../pkgs/morphir-host/connection/node-session.mts';
import type { Core } from '../../../pkgs/morphir-host/execution-client/contracts.mts';

// Exercise the shared adapter's publication boundary with an HTTP fixture.
// The CLI's real Rust authentication and lifecycle coverage lives in
// test-headless-connected.ts. This boundary uses only the core's JSON decoder.
const core: Core = command => JSON.stringify({ ok: true, value: JSON.parse(JSON.parse(command).source) });
const supported = process.platform !== 'win32' && !!process.getuid;
for (const stop of ['none', 'cancel', 'sigint', 'timeout'] as const) {
  test(`connected publication boundary: ${stop}`, { skip: !supported }, async () => {
    const root = mkdtempSync(join(tmpdir(), 'morphir-connected-session-'));
    const connection = join(root, 'connection.json');
    const listeners = process.listenerCount('SIGINT');
    let launches = 0;
    const server = createServer((request, response) => {
      if (request.url?.startsWith('/launch?')) {
        launches++;
        response.writeHead(302, { 'Set-Cookie': `morphir_session_test=${'A'.repeat(43)}; HttpOnly; SameSite=Strict; Path=/` }).end();
      } else {
        assert.equal(request.url, '/api/session');
        assert.equal(request.headers.cookie, `morphir_session_test=${'A'.repeat(43)}`);
        response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({
          protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'fixture-session', providers: [], initialSources: [],
        }));
      }
    });
    try {
      server.listen(0, '127.0.0.1');
      await once(server, 'listening');
      const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
      let cancelled = false;
      let selections = 0;
      const config = { source: `${origin}/launch?token=${'A'.repeat(43)}`, connection, timeout: stop === 'timeout' ? 200 : 5000 };
      const select = async () => {
        selections++;
        // These changes occur after the last HTTP await, so neither a later
        // request nor the periodic watcher can supply the publication check.
        if (stop === 'cancel') cancelled = true;
        if (stop === 'sigint') process.emit('SIGINT');
        if (stop === 'timeout') await new Promise(resolve => setTimeout(resolve, 250));
        return { selected: true };
      };
      // Existing callers can keep the four-argument shared API.
      const attempt = stop === 'none'
        ? establishConnection(config, core, () => false, select)
        : establishConnection(config, core, () => false, select, () => cancelled);
      if (stop === 'none') {
        assert.deepEqual(await attempt, { origin, sessionId: 'fixture-session' });
        assert.deepEqual(JSON.parse(readFileSync(connection, 'utf8')).descriptor, { selected: true });
      } else {
        await assert.rejects(attempt, error => error instanceof Refusal && error.code ===
          (stop === 'timeout' ? 'connected.timeout_before_submission' : 'connected.interrupted_before_submission'));
        assert.equal(existsSync(connection), false, 'Stopped selection must not publish credentials');
      }
      assert.equal(selections, 1, 'The test reaches the publication boundary after authenticated selection');
      assert.equal(launches, 1, 'The adapter never retries a one-use launch credential');
      assert.equal(process.listenerCount('SIGINT'), listeners, 'The owned signal listener is removed');
    } finally {
      server.closeAllConnections();
      await new Promise<void>(resolve => server.close(() => resolve()));
      rmSync(root, { recursive: true, force: true });
    }
  });
}
