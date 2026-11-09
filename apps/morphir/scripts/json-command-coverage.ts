import assert from 'node:assert/strict';

type Run = (args: string[], expected?: number) => { stdout: string; stderr: string };

// These are public command paths, independent of the parser's declarations.
const commands = [
  'run', 'execute', 'verify', 'conform', 'eval', 'worksheet', 'compile', 'version', 'generate',
  'model inspect', 'model export-original', 'notebook export', 'notebook import', 'connected connect', 'connected run',
  'connected artifacts', 'connected originals', 'workspace', 'workspace init',
  'project list', 'project add', 'project remove', 'toolchain info',
  'toolchain setup', 'toolchain build', 'toolchain run', 'toolchain exec', 'mck',
  'extension describe', 'extension compile', 'extension generate',
  'extension bundle', 'extension install', 'extension list', 'extension search',
  'extension update', 'extension uninstall', 'extension repository init',
  'extension repository add', 'extension repository list', 'extension repository inspect',
  'extension repository enable', 'extension repository disable', 'extension repository remove',
  'extension repository publish', 'extension repository verify',
];

export function exerciseJsonCommandCoverage(run: Run) {
  const root = JSON.parse(run(['--json', '--help']).stdout);
  assert.deepEqual(root.commands, commands);
  const version = JSON.parse(run(['version', '--json']).stdout);
  assert.equal(version.profile, 'morphir/command-result');
  assert.equal(version.contractVersion, '0.1.0');
  assert.equal(version.command, 'version');
  assert.equal(version.state, 'succeeded');
  assert.equal(version.exitCode, 0);
  assert.deepEqual(version.diagnostics, []);
  assert.equal(version.result.name, 'finos/morphir');
  assert.match(version.result.version, /^\d+\.\d+\.\d+$/);
  assert.equal(run(['version']).stdout.trim(), `Morphir ${version.result.version}`);
  assert.deepEqual(JSON.parse(run(['--json', 'version']).stdout), version);
  assert.deepEqual(JSON.parse(run(['version', '--json-lines']).stdout), { type: 'result', data: version });
  // Parent command help is an interface too, even without an operation.
  for (const path of ['', ...commands, 'model', 'connected', 'project', 'toolchain', 'extension', 'extension repository', 'notebook']) {
    const argv = path ? path.split(' ') : [];
    const human = run([...argv, '--help']);
    // Native Windows text stdout uses CRLF; JSON strings retain logical LF.
    // Compare help content without changing either public output channel.
    const humanText = human.stdout.replace(/\r\n/g, '\n');
    for (const args of [['--json', ...argv, '--help'], [...argv, '--help', '--json']]) {
      const result = run(args);
      assert.ok(result.stdout.endsWith('\n'));
      const help = JSON.parse(result.stdout);
      if (path === 'notebook' || path.startsWith('notebook ')) {
        assert.equal(help.profile, 'morphir/command-result');
        assert.equal(help.command, path.replace(' ', '.'));
        assert.equal(help.state, 'succeeded');
        assert.equal(humanText, help.result.help + '\n');
        continue;
      }
      assert.deepEqual(Object.keys(help).sort(), ['commands', 'options', 'usage']);
      assert.deepEqual(help.commands, commands);
      assert.ok(help.options.includes('--json'));
      assert.equal(humanText, 'Morphir CLI\n' + help.usage + '\n');
    }
    const events = run(['--json-lines', ...argv, '--help']);
    const lines = events.stdout.trimEnd().split(/\r?\n/);
    assert.equal(lines.length, 1);
    const event = JSON.parse(lines[0]!);
    if (path === 'notebook' || path.startsWith('notebook ')) {
      assert.equal(event.type, 'result');
      assert.equal(event.data.profile, 'morphir/command-result');
      assert.equal(humanText, event.data.result.help + '\n');
      continue;
    }
    assert.equal(event.type, 'help');
    assert.deepEqual(event.data.commands, commands);
    assert.equal(humanText, 'Morphir CLI\n' + event.data.usage + '\n');
  }
  // Refusals keep the established application schema and status, including
  // parser failures that occur before a command can be selected.
  for (const args of [
    ['--json', '--unknown'], ['--json', 'unknown'],
    ['version', 'unexpected', '--json'],
    ['--json', 'run', '--help', '--unknown'],
    ['--json', 'extension', 'compile', 'x.mbt', '--target', 'moonbit'],
  ]) {
    const result = run(args, 2);
    const failure = JSON.parse(result.stdout);
    assert.deepEqual(Object.keys(failure).sort(), ['committed', 'error', 'successful']);
    assert.equal(failure.successful, false);
    assert.deepEqual(failure.committed, []);
    assert.equal(typeof failure.error, 'string');
    assert.ok(result.stderr.replace(/\r\n/g, '\n').includes(failure.error),
      'Text diagnostics contain the JSON error, allowing native Windows CRLF');
  }
}
