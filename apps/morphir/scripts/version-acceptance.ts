import assert from 'node:assert/strict';
import {rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

export function exerciseVersion(
  directory: string,
  run: (args: string[], expected?: number) => {stdout: string; stderr: string},
  version: string,
) {
  const expected = {
    profile: 'morphir/command-result', contractVersion: '0.1.0',
    command: 'version', state: 'succeeded', exitCode: 0, diagnostics: [],
    result: {name: 'finos/morphir', version},
  };
  for (const args of [['version', '--json'], ['--json', 'version']]) {
    assert.deepEqual(JSON.parse(run(args).stdout), expected);
  }
  assert.equal(run(['version']).stdout.trim(), `Morphir ${version}`);
  assert.deepEqual(JSON.parse(run(['version', '--json-lines']).stdout), {type: 'result', data: expected});
  assert.match(JSON.parse(run(['version', '--help', '--json']).stdout).usage, /Usage: morphir version/);
  assert.equal(JSON.parse(run(['version', 'unexpected', '--json'], 2).stdout).successful, false);
  const config = join(directory, 'morphir.toml');
  writeFileSync(config, '[project\ninvalid =');
  try {
    const result = run(['version', '--json']);
    assert.deepEqual(JSON.parse(result.stdout), expected);
    assert.doesNotMatch(result.stderr, /invalid configuration|failed to load/i);
  } finally { rmSync(config); }
}
