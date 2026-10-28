import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const canonicalText = (text: string) => text.replace(/\r\n/g, '\n');

export function verifyConfigurationCorpus(workspace: string): void {
  const fixturePaths = execFileSync('git', ['ls-files', '-z', '--', 'tests', 'apps', 'pkgs'], {cwd: workspace, encoding: 'utf8'})
    .split('\0').filter(path => /(?:^|\/)morphir[^/]*\.toml$/.test(path) && (path.startsWith('tests/') || path.includes('/fixtures/'))).sort();
  const input = 'tests/configuration/toml-corpus.json';
  const corpus: Array<{path: string; text: string; sha256: string}> = JSON.parse(readFileSync(join(workspace, input), 'utf8'));
  assert.deepEqual(corpus.map(entry => entry.path).sort(), fixturePaths, 'Every tracked morphir*.toml fixture belongs to the parity corpus');
  for (const entry of corpus) {
    const text = canonicalText(readFileSync(join(workspace, entry.path), 'utf8'));
    assert.equal(entry.text, text, entry.path + ': parity snapshot is stale');
    assert.equal(entry.sha256, createHash('sha256').update(text, 'utf8').digest('hex'), entry.path + ': parity digest is stale');
  }
  const temporary = mkdtempSync(join(tmpdir(), 'morphir-config-parity-'));
  try {
    const output = join(temporary, 'corpus_generated_test.mbt');
    execFileSync('moon', ['tool', 'embed', '--text', '--name', 'toml_corpus_json', '--input', input, '--output', output], {cwd: workspace});
    assert.equal(canonicalText(readFileSync(join(workspace, 'pkgs/morphir-engine/config/corpus_generated_test.mbt'), 'utf8')), canonicalText(readFileSync(output, 'utf8')),
      'Regenerate the embedded configuration corpus with moon tool embed');
  } finally { rmSync(temporary, {recursive: true, force: true}); }
}
