import assert from 'node:assert/strict';

type Run = (args: string[], expected?: number) => { stdout: string; stderr: string };

// These are public command paths, independent of the parser's declarations.
const commands = [
  'run', 'execute', 'verify', 'conform', 'eval', 'worksheet', 'generate',
  'model inspect', 'model export-original', 'connected connect', 'connected run',
  'connected artifacts', 'connected originals', 'workspace', 'workspace init',
  'project list', 'project add', 'project remove', 'toolchain info',
  'toolchain setup', 'toolchain build', 'toolchain run', 'toolchain exec', 'mck',
  'extension describe', 'extension compile', 'extension generate',
];

export function exerciseJsonCommandCoverage(run: Run) {
  const root = JSON.parse(run(['--json', '--help']).stdout);
  assert.deepEqual(root.commands, commands);
  // Parent command help is an interface too, even without an operation.
  for (const path of ['', ...commands, 'model', 'connected', 'project', 'toolchain', 'extension']) {
    const argv = path ? path.split(' ') : [];
    const human = run([...argv, '--help']);
    // Native Windows text stdout uses CRLF; JSON strings retain logical LF.
    // Compare help content without changing either public output channel.
    const humanText = human.stdout.replace(/\r\n/g, '\n');
    for (const args of [['--json', ...argv, '--help'], [...argv, '--help', '--json']]) {
      const result = run(args);
      assert.ok(result.stdout.endsWith('\n'));
      const help = JSON.parse(result.stdout);
      assert.deepEqual(Object.keys(help).sort(), ['commands', 'options', 'usage']);
      assert.deepEqual(help.commands, commands);
      assert.ok(help.options.includes('--json'));
      assert.equal(humanText, 'Morphir CLI\n' + help.usage + '\n');
    }
    const events = run(['--json-lines', ...argv, '--help']);
    const lines = events.stdout.trimEnd().split(/\r?\n/);
    assert.equal(lines.length, 1);
    const event = JSON.parse(lines[0]!);
    assert.equal(event.type, 'help');
    assert.deepEqual(event.data.commands, commands);
    assert.equal(humanText, 'Morphir CLI\n' + event.data.usage + '\n');
  }
  // Refusals keep the established application schema and status, including
  // parser failures that occur before a command can be selected.
  for (const args of [
    ['--json', '--unknown'], ['--json', 'unknown'],
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
