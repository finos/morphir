import assert from 'node:assert/strict';
import test from 'node:test';
import {needsTerminalWorker} from './terminal-worker.mjs';

test('leading global controls keep interruptible commands in the owned worker', () => {
  for (const command of ['run', 'compile', 'execute', 'verify', 'conform', 'worksheet', 'eval', 'notebook', 'connected', 'model', 'generate', 'mck', 'workspace', 'project', 'toolchain', 'extension']) {
    assert.ok(needsTerminalWorker(['--json', '--profiles', 'metrics', '--log-level=trace', '--config', 'settings.toml', '--isolated', '--discovery-boundary', '.', '--suppress-warning=config.yaml_beside_toml', command]));
  }
});

test('control values and opaque child tokens never become the leading command', () => {
  assert.equal(needsTerminalWorker(['--config', 'worksheet']), false);
  assert.equal(needsTerminalWorker(['--profiles', 'model', 'unknown']), false);
  assert.equal(needsTerminalWorker(['unknown', 'run', 'worksheet', '--profiles', 'metrics']), false);
  assert.equal(needsTerminalWorker(['--', 'worksheet']), false);
  assert.equal(needsTerminalWorker(['--json', '--help']), false);
  assert.equal(needsTerminalWorker(['--log-level', 'debug', 'mck', 'check', '--profiles', '', '--']), true);
});
