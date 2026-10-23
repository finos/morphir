import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {delimiter, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Application regression: build each current artifact once, then exercise explicit
// argv against it. Historical source/artifact comparisons belong in local receipts.
const repository = fileURLToPath(new URL('../../../', import.meta.url));
const home = resolve(process.env.MOON_HOME || '.');
const moon = join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const moonrun = join(home, 'bin', process.platform === 'win32' ? 'moonrun.exe' : 'moonrun');
const env = {...process.env, MOON_HOME: home, PATH: join(home, 'bin') + delimiter + process.env.PATH};
const node = process.env.MORPHIR_FINITE_NODE || 'node';
const target = process.env.MORPHIR_FINITE_TARGET || 'js';
const section = process.env.MORPHIR_FINITE_SECTION || 'all';
const receipts = resolve(repository, process.env.MORPHIR_FINITE_RECEIPTS || `.dev/finite-json/tests-${target}`);
mkdirSync(receipts, {recursive: true});
const scratch = mkdtempSync(join(tmpdir(), 'morphir-finite-json-'));
const cases: object[] = [];
const builds: object[] = [];
const startedAt = Date.now();
let sequence = 0;
let primaryFailure: unknown;
const provenance: Record<string, unknown> = {
  repository, section, moonHome: home, node: {version: process.version, executable: process.execPath},
  environment: Object.fromEntries(['CI', 'GITHUB_SHA', 'GITHUB_REF', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
    'RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion', 'MOON_HOME', 'PATH',
    'MORPHIR_FINITE_SECTION', 'MORPHIR_FINITE_TARGET', 'MORPHIR_FINITE_RECEIPTS']
    .map(key => [key, process.env[key] ?? null])),
};

function sha256(bytes: string | Uint8Array) {
  return createHash('sha256').update(bytes).digest('hex');
}

function fileIdentity(path: string) {
  return {path, sha256: existsSync(path) ? sha256(readFileSync(path)) : null};
}

function receipt() {
  writeFileSync(join(receipts, 'cases.json'), JSON.stringify({target, section, host: `${process.platform}/${process.arch}`,
    startedAt: new Date(startedAt).toISOString(), elapsedMs: Date.now() - startedAt,
    provenance, builds, cases, ...(primaryFailure ? {failure: String(primaryFailure)} : {})}, null, 2) + '\n');
}

function probe(program: string, argv: string[], label: string) {
  const observed = spawnSync(program, argv, {cwd: repository, env, timeout: 15000, maxBuffer: 16 * 1024 * 1024});
  const stdout = observed.stdout || Buffer.alloc(0), stderr = observed.stderr || Buffer.alloc(0);
  writeFileSync(join(receipts, `${label}.stdout`), stdout);
  writeFileSync(join(receipts, `${label}.stderr`), stderr);
  return {command: [program, ...argv], status: observed.status, signal: observed.signal,
    error: observed.error?.message, stdout: stdout.toString('utf8'), stderr: stderr.toString('utf8'),
    stdoutSha256: sha256(stdout), stderrSha256: sha256(stderr)};
}

function build(paths: string[], backend: string) {
  // Fresh host qualification resolves the existing pinned dependencies once.
  // Other consumers keep their prebuilt/frozen producer contract.
  const argv = ['build', ...(section === 'pure-presentation' ? [] : ['--frozen']), '--target', backend, ...paths];
  const result = spawnSync(moon, argv, {
    cwd: repository, env, timeout: 300000, maxBuffer: 16 * 1024 * 1024,
  });
  const id = `build-${backend}-${sequence++}`;
  const stdout = result.stdout || Buffer.alloc(0), stderr = result.stderr || Buffer.alloc(0);
  writeFileSync(join(receipts, `${id}.stdout`), stdout);
  writeFileSync(join(receipts, `${id}.stderr`), stderr);
  builds.push({command: [moon, ...argv], cwd: repository, status: result.status, signal: result.signal,
    error: result.error?.message, stdout: `${id}.stdout`, stderr: `${id}.stderr`,
    stdoutSha256: sha256(stdout), stderrSha256: sha256(stderr)});
  receipt();
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, stderr.toString('utf8'));
}

function artifact(path: string, backend: string): string[] {
  const components = path.split('/');
  const module = components[1];
  const name = components.at(-1);
  assert.ok(module && name);
  const extension = backend === 'js' ? 'js' : backend === 'native' ? 'exe' : 'wasm';
  const binary = join(repository, '_build', backend, 'debug/build/finos', module,
    ...components.slice(2), `${name}.${extension}`);
  return backend === 'js' ? [node, binary] : backend === 'native' ? [binary] : [moonrun, binary, '--'];
}

function run(command: string[], argv: string[], label: string, input: Uint8Array = new Uint8Array(),
  extraEnv: NodeJS.ProcessEnv = {}) {
  const [program, ...prefix] = command;
  assert.ok(program);
  const result = spawnSync(program, [...prefix, ...argv], {
    cwd: scratch, env: {...env, ...extraEnv}, input, timeout: 180000, maxBuffer: 32 * 1024 * 1024,
  });
  const pure = label.startsWith('pkgs/') && !label.startsWith('pkgs/morphir-host/assembly/');
  const envelope = argv[0] === '--json' && (pure ?
    (argv.length > 1 || text.some(path => label.startsWith(path + '-'))) :
    (label.startsWith('extension-') || label.startsWith('otel-')) && argv.length !== 3);
  // Retain the original buffers before any strict assertion can fail.
  record(label, command, argv, result.status, result.signal,
    result.stdout || Buffer.alloc(0), result.stderr || Buffer.alloc(0), result.error?.message);
  assert.equal(result.error, undefined, `${label}: ${result.error?.message}`);
  const stdout = envelope ? nativeEnvelope(result.stdout) : result.stdout.toString('utf8');
  const stderr = result.stderr.toString('utf8');
  return {...result, stdout, stderr};
}

// Inspect the original bytes before decoding the newly owned native envelopes.
// ignoreBOM keeps a BOM visible, rather than silently removing it during decode.
function nativeEnvelope(bytes: Uint8Array): string {
  const stdout = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes);
  assert.ok(!(bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf), 'No UTF-8 BOM');
  assert.ok(!bytes.includes(0x0d), 'No CR bytes in native envelopes');
  const value = json(stdout);
  assert.equal(value.profile, 'morphir/command-result');
  assert.deepEqual(Buffer.from(bytes), Buffer.from(JSON.stringify(value) + '\n'), 'Exact compact object plus LF bytes');
  return stdout;
}

function record(label: string, command: string[], argv: string[], status: number | null,
  signal: string | null, stdout: string | Uint8Array, stderr: string | Uint8Array, error?: string) {
  const id = `${sequence++}-${label.replaceAll(/[^a-zA-Z0-9.-]/g, '_')}`;
  writeFileSync(join(receipts, `${id}.stdout`), stdout);
  writeFileSync(join(receipts, `${id}.stderr`), stderr);
  const backend = command[0] === node ? 'js' : command[0] === moonrun ? target : 'native';
  cases.push({label, backend, command, argv, cwd: scratch, status, signal, error, stdout: `${id}.stdout`, stderr: `${id}.stderr`,
    artifact: fileIdentity(command[0] === node || command[0] === moonrun ? command[1]! : command[0]!),
    stdoutSha256: sha256(stdout), stderrSha256: sha256(stderr)});
  receipt();
}

function json(stdout: string): Record<string, unknown> {
  const value: unknown = JSON.parse(stdout);
  assert.ok(value && typeof value === 'object' && !Array.isArray(value));
  assert.equal(stdout, JSON.stringify(value) + '\n', 'One compact JSON object followed by LF');
  return value as Record<string, unknown>;
}

function result(value: Record<string, unknown>): Record<string, unknown> {
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.state, 'succeeded');
  assert.equal(value.exitCode, 0);
  assert.deepEqual(value.diagnostics, []);
  assert.ok(value.result && typeof value.result === 'object');
  assert.ok(!('error' in value));
  return value.result as Record<string, unknown>;
}

function failure(command: string[], argv: string[], label: string, input?: Uint8Array) {
  const invocation = run(command, argv, label, input);
  assertFailure(invocation);
  return invocation;
}

function assertFailure(invocation: {status: number | null; stdout: string; stderr: string}) {
  assert.equal(invocation.status, 1, invocation.stderr);
  const value = json(invocation.stdout);
  assert.equal(value.state, 'failed');
  assert.equal(value.exitCode, 1);
  assert.equal(value.profile, 'morphir/command-result');
  assert.ok(value.error && typeof value.error === 'object');
  assert.ok(!('result' in value));
}

// Node owns the child's stdout pipe even when Bun launches this test. Bun's
// spawnSync drains differently and can hide an immediate process.exit truncation.
function nodePipeFailure(command: string[], argv: string[], label: string) {
  const collector = spawnSync(node, ['--input-type=module', '-e', `
import {spawnSync} from 'node:child_process';
const [program, ...prefix] = JSON.parse(process.argv[1]);
const child = spawnSync(program, [...prefix, ...JSON.parse(process.argv[2])], {
  encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
});
if (child.error) throw child.error;
process.stdout.write(JSON.stringify({status: child.status, signal: child.signal,
  stdout: child.stdout, stderr: child.stderr}));
`, JSON.stringify(command), JSON.stringify(argv)], {
    cwd: scratch, env, encoding: 'utf8', timeout: 15000, maxBuffer: 2 * 1024 * 1024,
  });
  assert.equal(collector.error, undefined, collector.error?.message);
  assert.equal(collector.status, 0, collector.stderr);
  assert.equal(collector.stderr, '');
  const invocation: {status: number | null; signal: string | null; stdout: string; stderr: string} =
    JSON.parse(collector.stdout);
  record(label, command, argv, invocation.status, invocation.signal, invocation.stdout, invocation.stderr);
  assertFailure(invocation);
  return invocation;
}

const bare = [
  'pkgs/morphir-elm/acceptance', 'pkgs/morphir-engine/acceptance',
  'pkgs/morphir-engine/acceptance/elm', 'pkgs/morphir-engine/acceptance/inference',
  'pkgs/morphir-moonbit/acceptance', 'pkgs/morphir-moonbit-frontend/acceptance',
  'pkgs/morphir-moonbit-frontend/library-acceptance', 'pkgs/morphir-moonbit-frontend/typed-acceptance',
  'pkgs/morphir-host/assembly/qualification',
];
const text = ['pkgs/morphir-engine/data/examples', 'pkgs/morphir-engine/examples',
  'pkgs/morphir-host/acceptance/metadata-fixture'];

try {
  receipt(); // An interrupted or failed run still identifies its requested environment.
  provenance.consumer = fileIdentity(fileURLToPath(import.meta.url));
  provenance.candidate = {head: probe('git', ['rev-parse', 'HEAD'], 'candidate-head'),
    status: probe('git', ['status', '--porcelain=v1'], 'candidate-status'),
    diff: probe('git', ['diff', '--binary', 'HEAD'], 'candidate-diff')};
  provenance.toolchain = {moon: probe(moon, ['version', '--all'], 'toolchain-moon'),
    bun: probe('bun', ['--version'], 'toolchain-bun'),
    moonBinary: fileIdentity(moon), moonrunBinary: fileIdentity(moonrun),
    mooncBinary: fileIdentity(join(home, 'bin', process.platform === 'win32' ? 'moonc.exe' : 'moonc')),
    corePin: fileIdentity(join(repository, 'tools', 'moonbit-core-pin.json')),
    coreManifest: fileIdentity(join(home, 'lib', 'core', 'moon.mod'))};
  const sourceList = probe('git', ['ls-files', '-z', '--', ...bare, ...text,
    'apps/morphir-extension/qualification', 'pkgs/morphir-host/platform/otel-live',
    'apps/morphir/scripts/test-finite-json-presentation.ts', 'tools/moonbit-core-pin.json',
    'moon.mod.json', 'moon.work', 'moon.work.json', 'moon.lock', '.github/workflows/headless-cli.yml'], 'source-list');
  provenance.sources = sourceList.stdout.split('\0').filter(Boolean).map(path => fileIdentity(resolve(repository, path)));
  provenance.sourceManifestSha256 = sha256(JSON.stringify(provenance.sources));
  receipt();
  assert.ok(process.env.MOON_HOME, 'Set MOON_HOME to the pinned MoonBit installation');
  assert.ok(['native', 'js', 'wasm', 'wasm-gc'].includes(target));
  assert.ok(['all', 'finite', 'portable', 'pure-presentation', 'extension', 'telemetry'].includes(section));
  if (['all', 'finite', 'portable', 'pure-presentation'].includes(section)) {
  const portable = [...bare, ...text].filter(path => !path.endsWith('assembly/qualification'));
  build(portable, target);
  if (section !== 'pure-presentation') build(['pkgs/morphir-host/assembly/qualification'], 'js');
  // Bounded actual-host consumer: build the eleven pure owners once and reuse
  // their artifacts for help, self-test and refusal.
  for (const path of section === 'pure-presentation' ? portable : [...bare, ...text]) {
    const backend = path.endsWith('assembly/qualification') ? 'js' : target;
    const command = artifact(path, backend);
    if (section === 'pure-presentation') {
      const help = run(command, ['--json', '--help'], `${path}-help`);
      assert.equal(help.status, 0);
      assert.equal(typeof result(json(help.stdout)).help, 'string');
      assert.equal(help.stderr, '');
      const selftest = run(command, ['--json', '--self-test'], `${path}-self-test`);
      assert.equal(selftest.status, 0, selftest.stderr);
      assert.equal(selftest.signal, null);
      assert.equal(selftest.stderr, '');
      assert.equal(result(json(selftest.stdout)).passed, true);
      const unknown = '--' + '\u0800'.repeat(24000);
      assert.ok(command.join(' ').length + unknown.length + 32 < 32767);
      for (const argv of [['--json', '--unknown'], ['--json', '\u03bb\ud83d\ude00'], ['--json', unknown]]) {
        const refused = failure(command, argv, `${path}-refusal`);
        assert.equal(refused.stderr, '');
        assert.equal(refused.signal, null);
        if (argv[1] === unknown) {
          assert.ok(Buffer.byteLength(refused.stdout) > 65536);
          const error = json(refused.stdout).error as Record<string, unknown>;
          assert.ok(String(error.message).startsWith(`error: unexpected argument '${unknown}' found\n`));
        }
      }
      continue;
    }
    const ordinary = run(command, [], `${path}-default`);
    assert.equal(ordinary.status, 0, ordinary.stderr);
    assert.equal(ordinary.stderr, '');
    const ignored = run(command, ['--', '--json', '', 'λ😀', '--help'], `${path}-legacy-literals`);
    assert.equal(ignored.status, 0);
    assert.equal(ignored.stdout, ordinary.stdout);
    for (const legacyArgv of [['--help'], ['--self-test'], ['--', '--json']]) {
      const legacy = run(command, legacyArgv, `${path}-legacy-control`);
      assert.equal(legacy.status, 0);
      assert.equal(legacy.stdout, ordinary.stdout);
    }
    const invocation = run(command, ['--json'], `${path}-json`);
    assert.equal(invocation.status, 0, invocation.stderr);
    assert.equal(invocation.stderr, '');
    const value = json(invocation.stdout);
    if (bare.includes(path)) {
      assert.equal(invocation.stdout, ordinary.stdout, 'Existing bare JSON schema and bytes');
    } else if (path.endsWith('morphir-engine/examples')) {
      const generated = result(value);
      assert.deepEqual(generated.diagnostics, []);
      assert.deepEqual(generated.artifacts, [{source: 'demo/src/main.scm', path: 'demo/dist/main.ir.json', evaluation: '42'}]);
      assert.equal(ordinary.stdout, 'demo/src/main.scm -> demo/dist/main.ir.json\nresult: 42\n');
    } else {
      const generated = result(value);
      assert.equal(generated.codec, 'ion-text');
      assert.equal(ordinary.stdout, String(generated.checkpoint) + '\n');
    }
    const help = run(command, ['--json', '--help'], `${path}-help`);
    assert.equal(help.status, 0);
    assert.equal(typeof result(json(help.stdout)).help, 'string');
    assert.equal(help.stderr, '');
    const selftest = run(command, ['--json', '--self-test'], `${path}-self-test`);
    assert.equal(selftest.status, 0, selftest.stderr);
    const tested = result(json(selftest.stdout));
    assert.equal(tested.passed, true);
    assert.deepEqual(tested.output, bare.includes(path) ? value : result(value));
    if (backend === 'js') {
      // Stay below Windows' 32,767 UTF-16 command-line limit while exceeding
      // 64 KiB on stdout. BMP Unicode uses three UTF-8 bytes per code unit.
      const unknown = '--' + '\u0800'.repeat(24000);
      assert.ok(command.join(' ').length + unknown.length + 32 < 32767,
        'Large failure fixture must fit the Windows command-line budget');
      const large = nodePipeFailure(command, ['--json', unknown], `${path}-large-failure-js`);
      assert.equal(large.signal, null);
      assert.equal(large.stderr, '');
      assert.ok(Buffer.byteLength(large.stdout) > 65536, 'Exercise buffered stdout');
      const value = json(large.stdout);
      assert.equal(value.command, path.replace(/^pkgs\//, '').replaceAll('/', '.'));
      assert.equal(value.contractVersion, '0.1.0');
      assert.deepEqual(value.diagnostics, []);
      const error = value.error as Record<string, unknown>;
      assert.equal(error.code, 'command.failed');
      assert.equal(typeof error.message, 'string');
      assert.ok((error.message as string).startsWith(`error: unexpected argument '${unknown}' found\n`),
        'The complete unknown-option payload must survive stdout completion');
    }
    for (const argv of [['--json', '--unknown'], ['--json', '--help', '--unknown'],
      ['--json', ''], ['--json', '--', '--help'], ['--json', 'λ😀']]) {
      assert.equal(failure(command, argv, `${path}-syntax`).stderr, '');
    }
  }

  }

  if (['all', 'finite', 'extension'].includes(section)) {
  const extension = 'apps/morphir-extension/acceptance';
  let extensionCommand: string[];
  if (section === 'extension') {
    const binary = process.env.MORPHIR_FINITE_EXTENSION_BINARY;
    assert.ok(binary, 'Extension qualification requires MORPHIR_FINITE_EXTENSION_BINARY');
    assert.ok(existsSync(resolve(binary)), 'The explicit current extension binary must exist');
    extensionCommand = [resolve(binary)];
  } else {
    build([extension], 'native');
    extensionCommand = artifact(extension, 'native');
  }
  for (const control of ['--help', '-h', '--self-test']) {
    const invocation = run(extensionCommand, ['--json', control], `extension-${control}`);
    assert.equal(invocation.status, 0);
    const output = result(json(invocation.stdout));
    if (control === '--self-test') { assert.equal(output.passed, true); assert.equal(output.cases, 3); }
    else { assert.equal(typeof output.help, 'string'); }
  }
  for (const argv of [['--json'], ['--json', '--unknown'], ['--json', '', 'λ😀', '--'],
    ['--json', '--json', '--help', '--'], ['--json', '--', '--json', '--help', '--']]) {
    failure(extensionCommand, argv, 'extension-failure');
  }
  const legacy = run(extensionCommand, ['--json', '--help', '--'], 'extension-literal-json-guest');
  assert.ok(legacy.status !== 0 || legacy.signal !== null);
  assert.equal(legacy.stdout, '', 'The complete triple remains literal legacy data');
  const stub = join(scratch, 'guest.mjs');
  const stubReceipt = join(scratch, 'guest-receipt.json');
  writeFileSync(stub, `import {writeFileSync} from 'node:fs';
writeFileSync(process.env.FINITE_STUB_RECEIPT, JSON.stringify({argv:process.argv.slice(2),cwd:process.cwd(),marker:process.env.FINITE_STUB_MARKER}));
process.stdout.write('child stdout remains collected protocol data');
process.stderr.write('child stderr fixture');process.exit(23);\n`);
  const nodeIdentity = spawnSync(node, ['-p', 'process.execPath'], {env, encoding: 'utf8'});
  assert.equal(nodeIdentity.status, 0, nodeIdentity.stderr);
  const stubResult = run(extensionCommand, ['--json', nodeIdentity.stdout.trim(), repository, join(scratch, 'evidence')],
    'extension-stub-failure', undefined, {MORPHIR_MEP_GUEST_ARGS: JSON.stringify([stub, '--json', '--', '', 'λ😀']),
      MORPHIR_MEP_GUEST_ENV: JSON.stringify({FINITE_STUB_RECEIPT: stubReceipt, FINITE_STUB_MARKER: 'explicit'})});
  assert.equal(stubResult.status, 1);
  assert.equal(json(stubResult.stdout).state, 'failed');
  assert.ok(!stubResult.stdout.includes('child stdout'));
  const child: {argv: string[]; cwd: string; marker: string} = JSON.parse(readFileSync(stubReceipt, 'utf8'));
  assert.deepEqual(child.argv, ['--json', '--', '', 'λ😀']);
  assert.equal(child.marker, 'explicit');
  assert.match(child.cwd.replaceAll('\\', '/'), /morphir-mep-acceptance-[^/]+\/process$/);

  }

  // Native telemetry builds separately from moon.work. Its existing setup owns
  // dependency acquisition; tests consume the explicit current artifact only.
  const otel = process.env.MORPHIR_FINITE_OTEL_BINARY;
  if (['all', 'telemetry'].includes(section) && otel) {
    const command = [resolve(otel)];
    for (const control of ['--help', '-h', '--self-test']) {
      const invocation = run(command, ['--json', control], `otel-${control}`);
      assert.equal(invocation.status, 0);
      const output = result(json(invocation.stdout));
      if (control === '--self-test') { assert.equal(output.passed, true); assert.equal(output.cases, 4); }
      else { assert.equal(typeof output.help, 'string'); }
    }
    for (const argv of [['--json'], ['--json', '--unknown'], ['--json', '', '', ''],
      ['--json', '--json', '--help', '--'], ['--json', '--', '--json', '--help', '--'],
      ...['0', '5001', 'bad', '-1', '--help', '--'].map(timeout => ['--json', 'http://127.0.0.1', 'http/json', timeout]),
      ['--json', 'http://127.0.0.1', '--help', '1'], ['--json', 'file:///tmp/local', 'http/json', '1']]) {
      assert.equal(failure(command, argv, 'otel-failure').stderr, 'observability.native_export_failed\n');
    }
    const literal = run(command, ['--json', '--help', '--'], 'otel-literal-json-endpoint');
    assert.equal(literal.status, 1);
    assert.equal(literal.stdout, '');
    assert.equal(literal.stderr, 'observability.native_export_failed\n');
    // Empty Ion datagram: real SDK construction, collection, flush and shutdown;
    // no exporter request is needed for the resulting empty batches.
    for (const protocol of ['http/json', 'http/protobuf']) {
      const invocation = run(command, ['--json', 'http://127.0.0.1:1', protocol, '1'], 'otel-empty-batch',
        Buffer.from([0xe0, 1, 0, 0xea]));
      assert.equal(invocation.status, 0, invocation.stderr);
      assert.deepEqual(result(json(invocation.stdout)), {spans: 0, logs: 0, metricBatches: 0,
        protocol, completion: 'exportersFlushedAndShutdown'});
    }
    // Generated by pinned ion/json + ion/binary from one completed observation
    // and one metrics row, using explicit Ion floats for the numeric fields.
    const fixture = Buffer.from('4AEA6u4Bo4GD3gGeh74Bmodwcm9maWxlhXN0YWdlhnNpZ25hbIx3YWxsX3NlY29uZHOOkGR1cmF0aW9uX3NlY29uZHOHc3Bhbl9pZIh0cmFjZV9pZIlwYXJlbnRfaWSLY29ycmVsYXRpb26KZGltZW5zaW9uc4Z0YXJnZXSIcHJvdmlkZXKHb3V0Y29tZYVjb3VudI6UZHVyYXRpb25fc2Vjb25kc19zdW3e+IqOlm1vcnBoaXItb2JzZXJ2YXRpb24tdjGLhGNhbGyMiWNvbXBsZXRlZI1IP/AAAAAAAACOSD/gAAAAAAAAj46QMDAwMDAwMDAwMDAwMDAwMZCOoDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAxkYCSD97Qio6SbW9ycGhpci1tZXRyaWNzLXYxk7643raLhGNhbGyUhm5hdGl2ZZWHZml4dHVyZZaJc3VjY2VlZGVkl0g/8AAAAAAAAJhIP+AAAAAAAAA=', 'base64');
    {
      const received: string[] = [];
      let refuse = false;
      const server = createServer(async (request, response) => {
        const chunks: Buffer[] = [];
        for await (const chunk of request) { chunks.push(Buffer.from(chunk)); }
        assert.equal(request.headers['content-type'], 'application/json');
        assert.ok(Buffer.concat(chunks).length > 0);
        received.push(request.url || '');
        response.writeHead(refuse ? 500 : 200, {'content-type': 'application/json'}).end('{}');
      });
      await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const address = server.address();
        assert.ok(address && typeof address !== 'string');
        const argv = ['--json', `http://127.0.0.1:${address.port}`, 'http/json', '1000'];
        const invoke = () => new Promise<{status: number | null; signal: string | null; stdout: string; stderr: string}>((resolve, reject) => {
          const child = spawn(command[0]!, argv, {cwd: scratch, env});
          const stdout: Buffer[] = [], stderr: Buffer[] = [];
          const timer = setTimeout(() => { child.kill(); reject(Error('Telemetry fixture timeout')); }, 10000);
          child.stdout.on('data', chunk => stdout.push(Buffer.from(chunk)));
          child.stderr.on('data', chunk => stderr.push(Buffer.from(chunk)));
          child.on('error', error => { clearTimeout(timer); reject(error); });
          child.on('close', (status, signal) => {
            clearTimeout(timer);
            try { resolve({status, signal, stdout: nativeEnvelope(Buffer.concat(stdout)), stderr: Buffer.concat(stderr).toString('utf8')}); }
            catch (error) { reject(error); }
          });
          child.stdin.end(fixture);
        });
        const observed = await invoke();
        record('otel-local-collector', command, argv, observed.status, observed.signal, observed.stdout, observed.stderr);
        assert.equal(observed.status, 0, observed.stderr);
        assert.deepEqual(result(json(observed.stdout)), {spans: 1, logs: 1, metricBatches: 2,
          protocol: 'http/json', completion: 'exportersFlushedAndShutdown'});
        assert.deepEqual(received, ['/v1/traces', '/v1/logs', '/v1/metrics']);
        refuse = true;
        const failed = await invoke();
        record('otel-exporter-refusal', command, argv, failed.status, failed.signal, failed.stdout, failed.stderr);
        assert.equal(failed.status, 1);
        const failure = json(failed.stdout);
        assert.equal(failure.state, 'failed');
        assert.equal(failure.exitCode, 1);
        assert.ok(!('result' in failure));
        assert.equal(failed.stderr, 'observability.native_export_failed\n');
      } finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
    }
  } else if (section === 'telemetry') {
    assert.fail('Telemetry qualification requires MORPHIR_FINITE_OTEL_BINARY');
  } else if (section === 'all') { console.log('Native telemetry not executed: supply MORPHIR_FINITE_OTEL_BINARY'); }
  console.log(`${cases.length} finite command cases passed on ${process.platform}/${process.arch}, target ${target}`);
} catch (error) {
  primaryFailure = error;
  throw error;
} finally {
  const secondaryFailures: unknown[] = [];
  for (const finish of [receipt, () => rmSync(scratch, {recursive: true, force: true})]) {
    try { finish(); } catch (error) { secondaryFailures.push(error); }
  }
  if (secondaryFailures.length) {
    if (!primaryFailure) throw secondaryFailures[0];
    console.error('Receipt or cleanup also failed:', secondaryFailures);
  }
}
