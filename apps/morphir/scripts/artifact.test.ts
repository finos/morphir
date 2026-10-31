import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {cliArtifact, stageCliArtifact} from './artifact.ts';

test('portable staging refuses stale outputs and qualifies the selected producer bytes', () => {
  const build = mkdtempSync(join(tmpdir(), 'morphir-artifacts-'));
  try {
    for (const target of ['js', 'wasm', 'wasm-gc']) {
      const canonical = join(build, target, `release/build/morphir/morphir/morphir.${target === 'js' ? 'js' : 'wasm'}`);
      mkdirSync(dirname(canonical), {recursive: true});
      writeFileSync(canonical, 'stale output');
      assert.throws(() => stageCliArtifact(build, target), /Missing CLI artifact/);
      const source = cliArtifact(build, target);
      mkdirSync(dirname(source), {recursive: true});
      const bytes = Buffer.from([0, 97, 115, 109, target === 'wasm' ? 1 : 2]);
      writeFileSync(source, bytes);
      assert.equal(stageCliArtifact(build, target), canonical);
      assert.deepEqual(readFileSync(canonical), bytes);
      writeFileSync(source, '');
      assert.throws(() => stageCliArtifact(build, target), /Missing CLI artifact/);
    }
  } finally { rmSync(build, {recursive: true, force: true}); }
});
