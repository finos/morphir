import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {verifyConfigurationCorpus} from './configuration-parity.ts';

for (const newline of ['\n', '\r\n']) {
  test(`configuration corpus handles ${newline === '\n' ? 'LF' : 'CRLF'} checkouts and rejects drift`, () => {
    const workspace = mkdtempSync(join(tmpdir(), 'morphir-corpus-checkout-'));
    const source = "[project]\nname='Example'\n";
    const path = 'tests/fixtures/morphir.toml';
    const input = 'tests/configuration/toml-corpus.json';
    const generated = 'pkgs/morphir-engine/workspace/corpus_generated_test.mbt';
    const put = (path: string, text: string) => {
      const full = join(workspace, path);
      mkdirSync(dirname(full), {recursive: true});
      writeFileSync(full, text.replace(/\r\n/g, '\n').replace(/\n/g, newline));
    };
    const git = (args: string[]) => execFileSync('git', ['-c', 'core.autocrlf=false', '-c', 'core.safecrlf=false', ...args],
      {cwd: workspace, stdio: 'ignore'});
    try {
      git(['init', '-q']);
      put(path, source);
      put(input, JSON.stringify([{path, text: source, sha256: createHash('sha256').update(source).digest('hex')}], null, 2) + '\n');
      mkdirSync(dirname(join(workspace, generated)), {recursive: true});
      execFileSync('moon', ['tool', 'embed', '--text', '--name', 'toml_corpus_json', '--input', input, '--output', generated], {cwd: workspace});
      const embedded = readFileSync(join(workspace, generated), 'utf8');
      put(generated, embedded);
      git(['add', '.']);
      verifyConfigurationCorpus(workspace);
      put(path, source.replace('Example', 'Changed'));
      assert.throws(() => verifyConfigurationCorpus(workspace), /parity snapshot is stale/);
      put(path, source);
      put(generated, embedded + '// stale generated data\n');
      assert.throws(() => verifyConfigurationCorpus(workspace), /Regenerate the embedded configuration corpus/);
      put(generated, embedded);
      put('tests/fixtures/morphir.extra.toml', source);
      git(['add', '.']);
      assert.throws(() => verifyConfigurationCorpus(workspace), /Every tracked morphir.*fixture belongs to the parity corpus/);
    } finally { rmSync(workspace, {recursive: true, force: true}); }
  });
}
