import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';

// This is a command-output regression, not a runtime, MEP, codec or MCK
// qualification. Its children are deliberately synthetic native MoonBit programs.
const names = ['codec-adapter-mck', 'package-codec-adapter', 'package-mep-extension',
  'portable-mep-check', 'portable-mep-cli', 'portable-mep-mck'] as const;
type Name = typeof names[number];
const hostModules = ['node-mep-cli.mjs', 'node-mep-stdio.mjs', 'node-mep-adapter.mjs', 'node-mep-worker.mjs',
  'mep-adapter.mjs', 'mep-frames.mjs', 'wasm-memory.mjs', 'node-artifacts.mjs', 'artifacts.mjs',
  'assembly.mjs', 'index.mjs', 'dist/bridge.mjs'];
const sha = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
const put = (path: string, data: string | Buffer) => {
  mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, data);
};
const copyExecutable = (from: string, to: string) => {
  mkdirSync(dirname(to), { recursive: true });
  try { linkSync(from, to); } catch { copyFileSync(from, to); }
};
const kit = {
  source: { package: { name: 'fixture/bool' }, sources: { documents: [{ text: 'fixture source 雪\n' }] } },
  plainIr: { fixture: true },
  consumer: { files: { 'moon.mod': 'fixture', 'moon.pkg': 'fixture', 'main.mbt': 'fixture' }, expectedStdout: 'fixture consumer passed\n' },
  expectedJsonArtifacts: { 'library.mbt': 'fixture library\n' },
};
type Journal = { program: string; executable: string; args: string[]; cwd: string; path: string | undefined; moonHome: string | undefined; tmpdir: string | undefined; stdin?: string };

// Self-contained native children continue working with PATH and MOON_HOME empty.
// Role selection follows the invoked hardlink name, just like the prior fixture.
const fixtureSource = String.raw`import {
  "moonbitlang/async@0.22.1",
  "moonbitlang/async@0.22.1/fs",
  "moonbitlang/async@0.22.1/stdio",
  "moonbitlang/core/env",
  "moonbitlang/core/json",
  "moonbitlang/x@0.5.5/sys",
}

fn env(name : String) -> String { @env.get_env_var(name).unwrap_or("") }
fn at(args : Array[String], flag : String) -> String {
  args[args.search(flag).unwrap() + 1]
}
fn has(args : Array[String], part : String) -> Bool {
  args.any(fn(arg) { arg.contains(part) })
}
fn parent(path : String) -> String {
  let parts = path.replace_all(old="\\", new="/").split("/").to_array()
  parts[:parts.length() - 1].join("/")
}
async fn put(path : String, text : String) -> Unit {
  if !@fs.exists(parent(path)) { @fs.mkdir(parent(path), recursive=true) }
  @fs.write_file(path, text)
}
async fn progress(program : String) -> Unit {
  @stdio.stdout.write("fixture " + program + " progress\n")
  @stdio.stderr.write("fixture " + program + " diagnostic\n")
}
async fn main {
  let argv = @env.args()
  let invoked = argv[0]
  let self = if invoked.contains("/") || invoked.contains("\\") { invoked } else { env("PATH") + "/" + invoked }
  let args = argv[1:].to_owned()
  let filename = self.replace_all(old="\\", new="/").split("/").to_array().last().unwrap().to_owned()
  let program = filename.strip_suffix(".exe").unwrap_or(filename[:]).to_owned()
  let fields : Map[String, Json] = {
    "program": Json(program), "executable": Json(self), "args": Json(args),
    "cwd": Json(@env.current_dir().unwrap()),
  }
  for pair in [("path", "PATH"), ("moonHome", "MOON_HOME"), ("tmpdir", "TMPDIR")] {
    let (key, variable) = pair
    if @env.get_env_var(variable) is Some(value) { fields[key] = Json(value) }
  }
  if env("PORTABLE_PROBE_STDIN") != "" {
    fields["stdin"] = Json(@stdio.stdin.read_all().text())
  }
  @fs.write_file(env("PORTABLE_JOURNAL"), Json::object(fields).stringify() + "\n", append=true, create_mode=OpenOrCreate)
  if env("PORTABLE_FAIL_PROGRAM") == program {
    @stdio.stdout.write("child failure stdout\n")
    @stdio.stderr.write("child failure stderr\n")
    @sys.exit(if env("PORTABLE_FAIL_CODE") == "130" { 130 } else { 23 })
  }
  let block = env("PORTABLE_BLOCK_FILE")
  if block != "" && (program == "mck" || program == "acceptance" || program == "git" ||
      (program == "node" && has(args, "node-package-"))) {
    if !@fs.exists(block) { @fs.mkdir(block, recursive=true) }
  }
  if program == "git" {
    if args[0] == "rev-parse" { @stdio.stdout.write("fixture-source-revision\n") }
  } else if program == "moon" {
    if args[0] == "version" { @stdio.stdout.write("moon 0.1 fixture\nmoonc v0.10.16+b1a0e846e\n") }
    else if args[0] == "run" { @stdio.stdout.write(env("PORTABLE_CORE") + "\n") }
    else if args.contains("tree") { @stdio.stdout.write("{\"fixtureGraph\":true}\n") }
    else if args.contains("--dry-run") { @stdio.stdout.write("fixture recipe\n") }
    else if args.contains("run") { @stdio.stdout.write("fixture consumer passed\n") }
    else { progress(program) }
  } else if program == "mck" {
    if args.contains("guest-run") {
      let report : Json = { "qualified": true, "suite": "mep-guest", "corpusSha256": env("MORPHIR_MEP_KIT_SHA256"), "records": [
        { "caseId": "generate-retained", "observed": { "result": { "artifacts": [{ "path": "library.mbt", "content": "fixture library\n", "binary": false }] } } },
        { "caseId": "compile-ion", "request": { "fixture": true } },
      ] }
      put(at(args, "--report"), report.stringify())
    } else if args.contains("run") {
      let report : Json = { "qualified": true, "errors": [], "records": [{ "fixture": true }] }
      put(at(args, "--report"), report.stringify())
      if has(args, "browser-byte-adapter") {
        let receipt : Json = { "shutdown": "passed", "preflight": "passed", "requests": 3 }
        put(args.last().unwrap(), receipt.stringify())
      }
    }
    progress(program)
  } else if program == "acceptance" { @stdio.stdout.write("fixture local acceptance\n") }
  else if program == "node" && args[0] == "-p" {
    @stdio.stdout.write(if args[1] == "process.execPath" { self + "\n" } else { "{\"fixtureRuntime\":true}\n" })
  } else if program == "node" && args[0] == "--version" { @stdio.stdout.write("v24.22.1\n") }
  else if program == "morphir" || (program == "node" && args.contains("extension")) {
    let operation = at(args, "extension")
    let source = args[args.search("extension").unwrap() + 2]
    let output = if args.contains("--output") { at(args, "--output") } else { "" }
    let pin = if args.contains("--extension-pin") { at(args, "--extension-pin") } else { "" }
    let mut code = 0
    let mut error = ""
    let mut result : Json = Json::empty_object()
    if args.contains("--cancel-file") { code = 130; error = "execution.cancelled" }
    else if args.contains("--timeout") { code = 124; error = "execution.deadline" }
    else if pin.contains("wrong-wasm") { code = 2; error = "extension.identity_mismatch" }
    else if pin.contains("component") { code = 2; error = "extension.unsupported_binding" }
    else if output == "mixed" { code = 2; error = "extension.unsupported_model_tuple" }
    else if output != "" && @fs.exists(output) { code = 2; error = "extension.output_exists" }
    else if ["lossy", "broken", "retired", "tampered"].contains(output) {
      code = 1; error = "extension.operation_unsuccessful"
      result = { "diagnostic": if output == "retired" { "moonbit_frontend.unsupported_profile" } else { "data.lossy_conversion" } }
    } else if operation == "compile" {
      guard source == "src/main.mbt" else { abort("unexpected fixture source") }
      put(output + "/model.ionb", "fixture model bytes\u0000")
      let envelope : Json = { "profile": "morphir-model", "payload": { "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" } }
      put(output + "/model-envelope.json", envelope.stringify())
    } else if operation == "generate" {
      put(output + "/library.mbt", "fixture library\n")
      put(output + "/mep/source-model.ionb", "fixture model bytes\u0000")
    } else { result = { "capabilities": { "cancellation": false } } }
    let report : Json = { "state": if code != 0 { "failed" } else { "completed" }, "error": error, "result": result,
      "extension": { "id": "morphir-moonbit" }, "access": { "wireCancellation": false },
      "lifecycle": { "exitCode": code, "workDirectoryEmpty": true, "shutdown": "acknowledged" },
      "negotiated": { "tuple": { "codec": "ion-binary" } } }
    @stdio.stdout.write(report.stringify() + "\n")
    @sys.exit(code)
  } else if program == "node" && has(args, "node-package-") {
    let codec = has(args, "node-package-codec-adapter")
    let destination = args[if codec { 2 } else { 1 }]
    for profile in (if codec { ["bytes-v1", "bytes-diagnostics-v1"] } else { ["extension"] }) {
      put(destination + "/" + profile + "/model.wasm", "fixture wasm")
      put(destination + "/" + profile + "/manifest.ion", "fixture ion")
    }
    progress(program)
  } else { progress(program) }
}
`;

function assertExited(child: ReturnType<typeof Bun.spawnSync>, argv: string[]) {
  const diagnostic = `${JSON.stringify(argv)}: timeout=${child.exitedDueToTimeout}, signal=${child.signalCode}, status=${child.exitCode}\n${child.stdout}\n${child.stderr}`;
  assert.equal(child.exitedDueToTimeout, false, diagnostic);
  assert.ok(child.signalCode == null, diagnostic);
  assert.notEqual(child.exitCode, null, diagnostic);
}

async function regression() {
  const began = performance.now();
  const root = resolve(import.meta.dir, '..');
  const builds: unknown[] = [];
  function build(argv: string[]) {
    const start = performance.now();
    const child = Bun.spawnSync(argv, { cwd: root, timeout: 90_000 });
    builds.push({ argv, code: child.exitCode, signal: child.signalCode ?? null, stdoutHex: child.stdout.toString('hex'), stderrHex: child.stderr.toString('hex'), stdout: child.stdout.toString(), stderr: child.stderr.toString(), timedOut: child.exitedDueToTimeout, milliseconds: performance.now() - start });
    assertExited(child, argv);
    assert.equal(child.exitCode, 0, JSON.stringify(argv) + child.stdout.toString() + child.stderr.toString());
    return child;
  }
  const receipts: unknown[] = [];
  const executables: Record<string, { path: string; sha256: string }> = {};
  const provenance = { candidate: Bun.spawnSync(['git', 'rev-parse', 'HEAD'], { cwd: root }).stdout.toString().trim(), githubSha: process.env.GITHUB_SHA, githubHeadSha: process.env.GITHUB_HEAD_SHA, consumer: { path: import.meta.path, sha256: sha(readFileSync(import.meta.path)) }, bun: { path: process.execPath, version: Bun.version, sha256: sha(readFileSync(process.execPath)) }, node: process.versions.node, moonHome: process.env.MOON_HOME };
  let failure: unknown;
  let scratch: string | undefined;
  let versionText: string | undefined;
  let fixtureIdentity: { bytes: number; sha256: string } | undefined;
  const target = process.env['PORTABLE_JSON_TARGET'] ?? 'native';
  try {
    const moon = Bun.which('moon');
    assert.ok(moon, 'Select the pinned MoonBit toolchain on PATH');
    executables.moon = { path: moon, sha256: sha(readFileSync(moon)) };
    assert.ok(target === 'native' || target === 'wasm');
    const moonrun = Bun.which('moonrun'); assert.ok(moonrun);
    const version = build([moon, 'version', '--all']);
    versionText = version.stdout.toString();
    assert.match(version.stdout.toString(), /0\.10\.16\+b1a0e846e/);
    assert.equal(Bun.version, '1.4.4');
    mkdirSync(join(root, '.dev'), { recursive: true });
    scratch = mkdtempSync(join(root, '.dev/portable-json-'));
    const executable = process.platform === 'win32' ? '.exe' : '';
    const artifacts = new Map<Name, string>();
    const fixturePath = join(scratch, 'fixture.mbtx');
    put(fixturePath, fixtureSource);
    build([moon, 'build', fixturePath, '--target', 'native']);
    const stubPath = join(scratch, '_build/fixture.mbtx/native/debug/build/single/single.exe');
    const fixtureBytes = readFileSync(stubPath);
    const fixtureHash = sha(fixtureBytes);
    fixtureIdentity = { bytes: fixtureBytes.length, sha256: fixtureHash };
    executables.fixture = { path: stubPath, sha256: fixtureHash };
    for (const name of names) {
      build([moon, 'build', `scripts/${name}.mbtx`, '--target', target]);
      artifacts.set(name, join(root, 'scripts/_build', `${name}.mbtx/${target}/debug/build/single/single.${target === 'native' ? 'exe' : 'wasm'}`));
      executables[name] = { path: artifacts.get(name)!, sha256: sha(readFileSync(artifacts.get(name)!)) };
    }
    let sequence = 0;
    // Keep a single PATH spelling on Windows, with no inherited host fallback.
    const fixtureEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toUpperCase() !== 'PATH'));
    function fixture() {
      const cwd = join(scratch!, `case-${sequence++} 雪 $;`);
      // Windows PATH uses semicolons as separators. Keep tool directories
      // representable while retaining Unicode, spaces and the literal ';' cwd.
      const bin = join(scratch!, `tools-${sequence} 雪`);
      const journal = join(cwd, 'journal.jsonl');
      for (const name of ['moon', 'node', 'bun', 'mck', 'git']) copyExecutable(stubPath, join(bin, name + executable));
      const artifactsPath = join(cwd, 'saved --json 雪');
      for (const profile of ['extension', 'bytes-v1', 'bytes-diagnostics-v1']) {
        put(join(artifactsPath, profile, 'model.wasm'), 'fixture wasm');
        put(join(artifactsPath, profile, 'manifest.ion'), 'fixture ion');
      }
      for (const name of hostModules) put(join(cwd, 'pkgs/morphir-host/embedding', name), `fixture ${name}\n`);
      for (const name of ['apps/morphir/bin/morphir.js', 'apps/morphir/dist/morphir.js',
        'apps/morphir/build-provider/extension.mjs', 'apps/morphir/build-provider/supervision.mjs',
        'apps/morphir/build-provider/identity.mjs']) put(join(cwd, name), `fixture ${name}\n`);
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/finos/morphir-extension/acceptance/acceptance.exe'));
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe'));
      // The filename is part of the existing primary CLI build path. Tell the
      // synthetic native child its role through a hardlink with that same name.
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/morphir/morphir/morphir.exe'));
      const kitPath = join(cwd, 'kit --json 雪.json'); put(kitPath, JSON.stringify(kit));
      const workbench = join(cwd, 'workbench'); put(join(workbench, 'cases.json'), JSON.stringify({ formatVersion: '0.1.0-draft.26', cases: [{}] }));
      const runner = join(bin, 'mck' + executable);
      const env: Record<string, string | undefined> = { ...fixtureEnv,
        PATH: bin, MOON_HOME: 'fixture preserved moon home 雪', PORTABLE_JOURNAL: journal, PORTABLE_CORE: 'fixture core --json 雪',
        MORPHIR_CODEC_ARTIFACTS: artifactsPath, MORPHIR_CODEC_EVIDENCE: join(cwd, 'codec-evidence'),
        MORPHIR_MEP_ARTIFACTS: artifactsPath, MORPHIR_MEP_EVIDENCE: join(cwd, 'local-evidence'),
        MORPHIR_MEP_MCK_EVIDENCE: join(cwd, 'mck-evidence'), MORPHIR_MEP_CLI_EVIDENCE: join(cwd, 'cli-evidence'),
        MORPHIR_MCK_BIN: runner, MORPHIR_MCK_SHA256: fixtureHash,
        MORPHIR_MEP_KIT: kitPath, MORPHIR_MEP_KIT_SHA256: sha(readFileSync(kitPath)), MORPHIR_WORKBENCH_KIT: workbench,
      };
      return { cwd, env, journal };
    }
    type Fixture = ReturnType<typeof fixture>;
    function run(name: Name, argv: string[], f: Fixture) {
      const begin = performance.now();
      const command = [...(target === 'wasm' ? [moonrun!] : []), artifacts.get(name)!, ...(target === 'wasm' ? ['--'] : []), ...argv];
      const child = Bun.spawnSync(command, { cwd: f.cwd, env: f.env, stdin: Buffer.from('fixture stdin 雪\n'), timeout: 90_000 });
      const result = { code: child.exitCode, signal: child.signalCode ?? null, stdoutHex: child.stdout.toString('hex'), stderrHex: child.stderr.toString('hex'), stdout: child.stdout.toString(), stderr: child.stderr.toString() };
      const row = { name, argv, command, cwd: f.cwd, stdin: 'fixture stdin 雪\n',
        environment: Object.fromEntries(['PATH', 'MOON_HOME', 'PORTABLE_FAIL_PROGRAM', 'PORTABLE_FAIL_CODE', 'PORTABLE_PROBE_STDIN', 'PORTABLE_BLOCK_FILE', 'MORPHIR_MCK_BIN', 'MORPHIR_MCK_SHA256', 'MORPHIR_MEP_KIT', 'MORPHIR_MEP_KIT_SHA256'].map(key => [key, f.env[key]])),
        timedOut: child.exitedDueToTimeout, ...result, journalText: existsSync(f.journal) ? readFileSync(f.journal, 'utf8') : '', children: [] as unknown[], milliseconds: performance.now() - begin };
      receipts.push(row);
      assertExited(child, command);
      row.children = row.journalText.trim() ? row.journalText.trim().split('\n').map(line => JSON.parse(line)) : [];
      for (const entry of row.children as Journal[]) {
        assert.equal(sha(readFileSync(entry.executable)), fixtureHash, 'Resolved child is the native fixture');
      }
      return result;
    }
    function decoded(outcome: ReturnType<typeof run>, state: string, code: number) {
      assert.equal(outcome.code, code, outcome.stderr + outcome.stdout);
      const bytes = Buffer.from(outcome.stdoutHex, 'hex');
      assert.equal(bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), false, 'No UTF-8 BOM');
      assert.equal(bytes.at(-1), 0x0a, 'One terminal LF');
      assert.equal(bytes.includes(0x0d), false, 'No physical CR');
      assert.equal(bytes.filter(byte => byte === 0x0a).length, 1, 'One physical LF');
      assert.equal(new TextDecoder('utf-8', { fatal: true }).decode(bytes), outcome.stdout);
      const value = JSON.parse(outcome.stdout);
      assert.equal(outcome.stdout, JSON.stringify(value) + '\n', 'Exactly one compact JSON value plus LF');
      assert.equal(value.profile, 'morphir/command-result'); assert.equal(value.contractVersion, '0.1.0');
      assert.equal(value.state, state); assert.equal(value.exitCode, code); assert.deepEqual(value.diagnostics, []);
      if (state === 'succeeded') { assert.ok(value.result); assert.ok(!('error' in value)); }
      else { assert.equal(typeof value.error.message, 'string'); assert.ok(!('result' in value)); }
      return value;
    }
    const journal = (f: Fixture): Journal[] => existsSync(f.journal) ? readFileSync(f.journal, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
    for (const name of names) {
      const help = fixture();
      const rendered = decoded(run(name, ['--json', '--help'], help), 'succeeded', 0);
      assert.match(rendered.result.render_help, /Usage:/); assert.match(rendered.result.json_help, /error\.code\/message/);
      assert.match(rendered.result.json_help, /legacy child-failure branches exit 1/);
      assert.deepEqual(journal(help), []);
      for (const argv of [['--json', '-h'], ['--json', '--help', '--json'], ['--json', 'help'], ['--json', 'help', '--help']]) decoded(run(name, argv, help), 'succeeded', 0);
      for (const argv of [['--json', '--unknown'], ['--json', '--json=literal']]) {
        decoded(run(name, argv, help), 'failed', 1); assert.deepEqual(journal(help), []);
      }
      const stdinProbe = fixture(); stdinProbe.env['PORTABLE_PROBE_STDIN'] = '1';
      stdinProbe.env['PORTABLE_FAIL_PROGRAM'] = 'moon';
      decoded(run(name, ['--json'], stdinProbe), 'failed', 1);
      assert.equal(journal(stdinProbe)[0]?.stdin, 'fixture stdin 雪\n');
      const success = fixture();
      const result = decoded(run(name, ['--json'], success), 'succeeded', 0);
      assert.equal(result.command, name.replaceAll('-', '.'));
      const launches = journal(success); assert.ok(launches.length > 0);
      assert.ok(launches.every(entry => entry.cwd === success.cwd || entry.cwd.startsWith(success.cwd + sep)));
      assert.ok(launches.some(entry => entry.path === success.env['PATH'] && entry.moonHome === success.env['MOON_HOME']));
      if (name.startsWith('package-')) {
        assert.equal(readFileSync(join(result.result.destination, 'core-graph.json'), 'utf8'), '{"fixtureGraph":true}\n');
        assert.equal(readFileSync(join(result.result.destination, 'recipe.txt'), 'utf8'), 'fixture recipe\n');
        assert.deepEqual(launches.map(entry => entry.program), ['moon', 'moon', 'moon', 'bun', 'node']);
      } else {
        const ion = name === 'portable-mep-cli' ? 'receipt.ion' : name === 'portable-mep-check' ? 'portable-receipt.ion' : 'qualification.ion';
        const directory = name === 'portable-mep-cli' ? 'cli-evidence' : name === 'portable-mep-check' ? 'local-evidence' : name === 'portable-mep-mck' ? 'mck-evidence' : 'codec-evidence';
        const text = readFileSync(join(success.cwd, directory, ion), 'utf8');
        assert.deepEqual(JSON.parse(text.slice(text.indexOf('::') + 2)), result.result);
      }
      if (name === 'portable-mep-mck') {
        const guests = launches.filter(entry => entry.args.includes('guest-run'));
        assert.equal(guests.length, 2); assert.ok(guests.every(entry => entry.path === '' && entry.moonHome === ''));
      }
      if (name === 'portable-mep-check') {
        const acceptance = launches.find(entry => entry.program === 'acceptance')!;
        assert.ok(acceptance); assert.ok(acceptance.args[1] === success.cwd);
      }
      if (name === 'portable-mep-cli') {
        const calls = launches.filter(entry => entry.args.includes('extension'));
        assert.equal(calls.length, 28); assert.ok(calls.every(entry => entry.args[0] === '--json' || entry.args[1] === '--json'));
        for (const entry of calls) {
          assert.ok(entry.program === 'node' || entry.program === 'morphir');
          const backend = entry.program === 'node' ? 'js' : 'native';
          const evidence = success.env['MORPHIR_MEP_CLI_EVIDENCE']!;
          assert.equal(entry.cwd, join(evidence, backend));
          // The wrapper forwards this literal string; the OS normalizes cwd
          // separately. Keep exact environment bytes, including mixed slashes.
          assert.equal(entry.tmpdir, `${evidence}/${backend}/tmp`);
        }
        assert.ok(result.result.hosts.every((host: { cases: unknown[] }) => host.cases.length === 14));
      }
      for (const code of [23, 130]) {
        const failure = fixture(); failure.env['PORTABLE_FAIL_PROGRAM'] = 'moon'; failure.env['PORTABLE_FAIL_CODE'] = String(code);
        const failed = run(name, ['--json'], failure);
        const value = decoded(failed, 'failed', 1); assert.match(value.error.message, new RegExp(`child exit ${code}`), failed.stderr + failed.stdout); assert.equal(value.error.code, 'child.failed'); assert.match(failed.stderr, /child failure/); assert.equal(journal(failure).length, 1);
      }
      const laterFailure = fixture();
      laterFailure.env['PORTABLE_FAIL_PROGRAM'] = name === 'codec-adapter-mck' || name === 'portable-mep-mck' ? 'mck' : name === 'portable-mep-check' ? 'acceptance' : 'bun';
      const later = decoded(run(name, ['--json'], laterFailure), 'failed', 1);
      assert.match(later.error.message, /child exit 23/);
      const laterChildren = journal(laterFailure);
      assert.equal(laterChildren.at(-1)?.program, laterFailure.env['PORTABLE_FAIL_PROGRAM']);
      assert.equal(laterChildren.filter(entry => entry.program === laterFailure.env['PORTABLE_FAIL_PROGRAM']).length, 1);
      for (const code of [23, 130]) {
        const f = fixture(); f.env['PORTABLE_FAIL_PROGRAM'] = 'moon'; f.env['PORTABLE_FAIL_CODE'] = String(code);
        const legacyChild = run(name, [], f);
        assert.equal(legacyChild.code, 1, legacyChild.stdout + legacyChild.stderr);
        assert.throws(() => JSON.parse(legacyChild.stdout));
        assert.equal(journal(f).length, 1);
      }
      const writeFailure = fixture();
      if (name.startsWith('package-')) {
        put(join(writeFailure.env['MORPHIR_CODEC_ARTIFACTS']!, 'core-graph.json'), 'placeholder');
        // A directory at the owned output path makes the actual completed write fail.
        const destination = name === 'package-codec-adapter' ? writeFailure.env['MORPHIR_CODEC_ARTIFACTS']! : writeFailure.env['MORPHIR_MEP_ARTIFACTS']!;
        rmSync(join(destination, 'core-graph.json'), { force: true });
        mkdirSync(join(destination, 'core-graph.json'));
      } else {
        const directory = name === 'codec-adapter-mck' ? 'codec-evidence' : name === 'portable-mep-check' ? 'local-evidence' : name === 'portable-mep-cli' ? 'cli-evidence' : 'mck-evidence';
        const file = name === 'portable-mep-check' ? 'portable-receipt.ion' : name === 'portable-mep-cli' ? 'receipt.ion' : 'qualification.ion';
        writeFailure.env['PORTABLE_BLOCK_FILE'] = join(writeFailure.cwd, directory, file);
      }
      decoded(run(name, ['--json'], writeFailure), 'failed', 1);
      assert.ok(journal(writeFailure).length > 0);
      const refusal = fixture();
      if (name.startsWith('package-')) refusal.env['PORTABLE_FAIL_PROGRAM'] = 'missing';
      else if (name === 'codec-adapter-mck') delete refusal.env['MORPHIR_MCK_BIN'];
      else if (name === 'portable-mep-cli') refusal.env['MORPHIR_MEP_KIT_SHA256'] = 'wrong';
      else if (name === 'portable-mep-mck') refusal.env['MORPHIR_MCK_SHA256'] = 'wrong';
      else mkdirSync(refusal.env['MORPHIR_MEP_EVIDENCE']!);
      if (!name.startsWith('package-')) { decoded(run(name, ['--json'], refusal), 'failed', 1); assert.equal(journal(refusal).length, 0); }
      const missing = fixture(); missing.env['PATH'] = join(missing.cwd, 'no-tools');
      decoded(run(name, ['--json'], missing), 'failed', 1);
      // Legacy wrappers ignored operands. Neither variadic parsing nor new JSON
      // dispatch may reinterpret an escaped flag or rebuild a foreign tail.
      if (name !== 'portable-mep-cli') {
        const defaults = fixture();
        const legacy = run(name, ['--', '--json', '', '雪', '--', '--help', '--json=literal'], defaults);
        assert.equal(legacy.code, 0, legacy.stdout + legacy.stderr);
        assert.throws(() => JSON.parse(legacy.stdout));
        const escaped = fixture();
        decoded(run(name, ['--json', '--', '--json', '', '雪', '--', '--help'], escaped), 'succeeded', 0);
      }
      const legacyFailure = run(name, [], writeFailure);
      assert.notEqual(legacyFailure.code, 0, 'Default failure retains its backend presentation');
      const baseline = target === 'native' ? process.env['PORTABLE_JSON_BASELINE'] : undefined;
      if (baseline) {
        const f = fixture();
        const candidate = run(name, [], f);
        assert.equal(candidate.code, 0, candidate.stdout + candidate.stderr);
        const candidateChildren = journal(f);
        rmSync(f.journal, { force: true });
        const snapshots = new Map<string, Buffer>();
        function snapshot(directory: string) {
          if (!existsSync(directory)) return;
          for (const entry of readdirSync(directory, { withFileTypes: true })) {
            const file = join(directory, entry.name);
            if (entry.isDirectory()) snapshot(file); else snapshots.set(file, readFileSync(file));
          }
        }
        for (const key of ['MORPHIR_CODEC_EVIDENCE', 'MORPHIR_MEP_EVIDENCE', 'MORPHIR_MEP_MCK_EVIDENCE', 'MORPHIR_MEP_CLI_EVIDENCE']) snapshot(f.env[key]!);
        if (name.startsWith('package-')) for (const file of ['core-graph.json', 'recipe.txt']) snapshots.set(join(f.env['MORPHIR_CODEC_ARTIFACTS']!, file), readFileSync(join(f.env['MORPHIR_CODEC_ARTIFACTS']!, file)));
        for (const key of ['MORPHIR_CODEC_EVIDENCE', 'MORPHIR_MEP_EVIDENCE', 'MORPHIR_MEP_MCK_EVIDENCE', 'MORPHIR_MEP_CLI_EVIDENCE']) rmSync(f.env[key]!, { recursive: true, force: true });
        const original = artifacts.get(name)!;
        artifacts.set(name, join(baseline, name + '.exe'));
        const old = run(name, [], f);
        assert.deepEqual(old, candidate, 'Default success bytes and status must match the supplied baseline');
        assert.deepEqual(journal(f), candidateChildren, 'Default child argv/cwd/env/order must match');
        for (const [file, bytes] of snapshots) assert.deepEqual(readFileSync(file), bytes, file);
        artifacts.set(name, original);
        artifacts.set(name, join(baseline, name + '.exe'));
        const baselineFailure = run(name, [], writeFailure);
        assert.equal(baselineFailure.code, legacyFailure.code);
        assert.equal(baselineFailure.signal, legacyFailure.signal);
        artifacts.set(name, original);
        if (name === 'portable-mep-cli') {
          const now = run(name, ['--help'], f); artifacts.set(name, join(baseline, name + '.exe'));
          assert.deepEqual(run(name, ['--help'], f), now); artifacts.set(name, original);
        }
      }
      console.log(`${name}: completed result, help, refusals, child 23/130, channels and legacy operands passed`);
    }
  } catch (error) { failure = error; throw error; }
  finally {
    const errors: unknown[] = [];
    try {
      const receiptPath = process.env['PORTABLE_JSON_RECEIPTS'];
      if (receiptPath) put(receiptPath, JSON.stringify({ toolchain: versionText, bun: Bun.version, platform: process.platform, arch: process.arch, target, provenance, executables, fixture: fixtureIdentity, builds, milliseconds: performance.now() - began, failure: failure === undefined ? null : String(failure), count: receipts.length, receipts }, null, 2) + '\n');
    } catch (error) { errors.push(error); }
    try { if (scratch) rmSync(scratch, { recursive: true, force: true }); } catch (error) { errors.push(error); }
    if (errors.length) throw new AggregateError(failure === undefined ? errors : [failure, ...errors], 'Receipt/cleanup failed; original failure retained');
  }
}

await regression();
