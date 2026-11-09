import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Worker} from 'node:worker_threads';
import {headlessEnvironment} from './headless-environment.ts';

/** Discovery must tolerate an ancestor changing while its entries are read. */
export async function exerciseNativeDiscoveryChurn(binary: string) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-discovery-churn-')));
  const app = join(root, 'app');
  mkdirSync(app);
  writeFileSync(join(root, 'morphir.toml'), "[project]\nname='Churn'\n");
  const env = headlessEnvironment(join(root, 'cli-environment'));
  const run = () => spawnSync(binary, ['project', 'list', '--json', '--isolated', '--discovery-boundary', root], {
    cwd: app, env, encoding: 'utf8', timeout: 15_000,
  });
  const cycles = new Int32Array(new SharedArrayBuffer(4));
  const writer = new Worker(new URL('data:text/javascript,' + encodeURIComponent(`
    import {workerData, parentPort} from 'node:worker_threads';
    import {writeFileSync, unlinkSync} from 'node:fs';
    const cycles = new Int32Array(workerData.cycles);
    for (let i = 0; i < 300; i++) writeFileSync(workerData.root + '/churn-' + i, '');
    parentPort.postMessage('ready');
    while (true) {
      for (let i = 0; i < 300; i++) unlinkSync(workerData.root + '/churn-' + i);
      for (let i = 0; i < 300; i++) writeFileSync(workerData.root + '/churn-' + i, '');
      Atomics.add(cycles, 0, 1);
    }
  `)), {workerData: {root, cycles: cycles.buffer}});
  try {
    await once(writer, 'message');
    for (let i = 0; i < 100; i++) {
      const result = run();
      const context = `native discovery churn iteration ${i}: ${result.error?.message ?? ''}\n${result.stderr}`;
      assert.equal(result.error, undefined, context);
      assert.equal(result.signal, null, context);
      const report = JSON.parse(result.stdout);
      if (result.status === 0) {
        assert.deepEqual(report.projects.map((project: {name: string}) => project.name), ['Churn'], context);
      } else {
        // A removed name can disappear before kind inspection. Discovery keeps
        // its existing fail-closed refusal instead of inventing a snapshot.
        assert.equal(result.status, 2, context);
        assert.equal(report.successful, false, context);
        assert.match(result.stderr, /Unreadable or unsupported entry: churn-\d+/, context);
      }
    }
    assert.ok(Atomics.load(cycles, 0) > 0, 'the writer changed the directory during qualification');
  } finally {
    await writer.terminate();
    try {
      const stable = run();
      assert.equal(stable.status, 0, stable.stderr);
      assert.deepEqual(JSON.parse(stable.stdout).projects.map((project: {name: string}) => project.name), ['Churn']);
    } finally { rmSync(root, {recursive: true, force: true}); }
  }
}

/** Run against each actual CLI host, using the public controls of an isolated driver. */
export function exerciseConfiguration(
  directory: string,
  run: (args: string[], expected?: number, cwd?: string) => {stdout: string; stderr: string},
  target: string,
) {
  const root = join(directory, 'configuration');
  const put = (path: string, text: string) => {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), text);
  };
  const invoke = (args: string[], expected = 0, cwd = root) =>
    run(['--isolated', '--discovery-boundary', '.', ...args], expected, cwd);
  const list = (...args: string[]) => JSON.parse(invoke(['project', 'list', '--json', ...args]).stdout);
  put('morphir.json', "// JSON5 in a .json file\n{project:{name:'Shop'},frontend:{language:'elm'},pipeline:{backend:'scala'},}");
  put('morphir.yaml', 'frontend:\n  language: moonbit\n');
  put('morphir.toml', "frontend.language='scheme'\n[profiles]\ndefault=['metrics']\n");
  put('morphir.profile.metrics.toml', "pipeline.backend='javascript'\n");
  put('morphir.profile.audit.json5', "{pipeline:{backend:'ir-json'}}");
  const mixed = invoke(['project', 'list', '--json']);
  assert.equal(JSON.parse(mixed.stdout).projects[0].frontend, 'scheme');
  assert.equal(JSON.parse(mixed.stdout).projects[0].target, 'javascript');
  assert.match(mixed.stderr, /config.yaml_beside_toml/);
  assert.match(mixed.stderr, /config.json_keys_below_toml/);
  assert.equal(list('--no-profiles').projects[0].target, 'scala');
  assert.equal(list('--profiles', 'audit').projects[0].target, 'ir-json');
  assert.equal(list('--profiles', 'metrics', '--profiles', 'audit').projects[0].target, 'ir-json');
  assert.equal(list('--profiles', 'audit,metrics').projects[0].target, 'javascript');
  assert.equal(list('--config', 'morphir.json').projects[0].frontend, 'elm');
  put('selected.yml', 'frontend:\n  language: moonbit\n');
  assert.equal(list('--config', 'selected.yml').projects[0].frontend, 'moonbit');
  assert.ok(!invoke(['project', 'list', '--json', '--suppress-warning', 'config.yaml_beside_toml']).stderr.includes('config.yaml_beside_toml'));
  assert.match(invoke(['project', 'list', '--json', '--suppress-warning', 'not-a-warning']).stderr, /Unknown configuration warning code: not-a-warning/);
  put('morphir.user.toml', "pipeline.backend='scala'\n");
  assert.equal(JSON.parse(run(['--discovery-boundary', '.', 'project', 'list', '--json', '--profiles', 'metrics'], 0, root).stdout).projects[0].target, 'scala');
  assert.equal(list('--profiles', 'metrics').projects[0].target, 'javascript');
  for (const args of [['--profiles', 'audit,,metrics'], ['--profiles', 'audit', '--no-profiles'], ['--config', 'missing.xml']]) {
    const result = invoke(['project', 'list', '--json', ...args], 2);
    assert.equal(JSON.parse(result.stdout).successful, false);
  }
  assert.match(invoke(['project', 'list', '--config', 'missing.scm', '--json'], 2).stdout, /--config-script/);

  put('parent/morphir.toml', "[workspace]\nmembers=['app']\n[frontend]\nlanguage='elm'\n");
  put('parent/app/morphir.toml', "[project]\nname='App'\n");
  const app = join(root, 'parent/app');
  const bounded = JSON.parse(invoke(['project', 'list', '--json'], 0, app).stdout);
  assert.equal(bounded.projects[0].frontend, 'scheme');
  // WASI only sees ancestors inside its preopened development root.
  if (target !== 'wasm') {
    const inherited = JSON.parse(run(['--isolated', 'project', 'list', '--json'], 0, app).stdout);
    assert.equal(inherited.projects[0].frontend, 'elm');
  }
  // The public controls are read-only and leave lower-format sources intact.
  assert.match(readFileSync(join(root, 'morphir.json'), 'utf8'), /JSON5/);
}
