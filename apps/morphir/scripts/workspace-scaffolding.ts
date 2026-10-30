import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

/** Qualify the shared scaffolding through the real CLI on each supported runtime. */
export function exerciseScaffolding(
  directory: string,
  run: (args: string[], expected?: number, cwd?: string) => { stdout: string; stderr: string },
) {
  const root = join(directory, 'scaffolding');
  mkdirSync(root);
  const invoke = (args: string[], expected = 0) => run(args, expected, root);
  const initial = JSON.parse(invoke(['workspace', 'init', '--json']).stdout);
  assert.equal(initial.successful, true);
  assert.equal(JSON.parse(invoke(['workspace', '--json']).stdout).projects.length, 0);
  const config = '# Personal comment\n[workspace]\nmembers = ["packages/*"] # keep\n\n[frontend]\nlanguage = "scheme"\n';
  writeFileSync(join(root, 'morphir.toml'), config);
  for (const name of ['one', 'two']) {
    const result = JSON.parse(invoke(['project', 'add', `packages/${name}`, '--name', name, '--json']).stdout);
    assert.equal(result.successful, true);
  }
  assert.equal(readFileSync(join(root, 'morphir.toml'), 'utf8'), config);
  const projects = JSON.parse(invoke(['workspace', '--json']).stdout);
  assert.equal(projects.protocolVersion, '0.1.0');
  assert.deepEqual(projects.projects.map((p: { relativePath: string }) => p.relativePath), ['packages/one', 'packages/two']);
  const built = JSON.parse(invoke(['run', '--json']).stdout);
  assert.equal(built.successful, true);
  assert.equal(built.processed, 2);
  invoke(['project', 'add', 'packages/one', '--name', 'duplicate', '--json'], 2);
  invoke(['project', 'add', '../escape', '--name', 'Escape', '--json'], 2);
  invoke(['project', 'add', 'missing-name', '--json'], 2);
  const removed = invoke(['project', 'remove', 'packages/one', '--json-lines']).stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
  assert.equal(removed[0].type, 'workspace-edit');
  assert.ok(existsSync(join(root, 'packages/one/src/main.scm')));
  invoke(['project', 'remove', 'packages/two', '--delete', '--json']);
  assert.ok(!existsSync(join(root, 'packages/two')));
  assert.equal(JSON.parse(invoke(['workspace', '--json']).stdout).projects.length, 0);
  invoke(['project', 'add', '.', '--name', 'Root', '--language', 'scheme', '--json']);
  const selected = JSON.parse(invoke(['run', '--project', '.', '--json']).stdout);
  assert.equal(selected.successful, true);
  assert.equal(selected.processed, 1);
  invoke(['project', 'remove', '.', '--delete', '--json'], 2);
  invoke(['project', 'remove', '.', '--json']);
  assert.equal(JSON.parse(invoke(['workspace', '--json']).stdout).projects.length, 0);
  assert.ok(!existsSync(join(root, '.morphir-workspace-edit.lock')));
  invoke(['workspace', '--all', '--json'], 2);
  invoke(['workspace', '--dry-run', '--json'], 2);
  invoke(['workspace', '--file', '--json'], 2);
  invoke(['workspace', '--directory', '--json'], 2);

  for (const language of ['elm', 'moonbit']) {
    const folder = join(directory, `starter-${language}`);
    mkdirSync(folder);
    run(['workspace', 'init', '--project', 'Starter', '--language', language, '--json'], 0, folder);
    const report = JSON.parse(run(['run', '--json'], 0, folder).stdout);
    assert.equal(report.successful, true, language);
  }

  for (const [filename, content] of [
    ['morphir.json', '{workspace:{members:["existing"]}}'],
    ['morphir.yaml', 'workspace:\n  members: [existing]\n'],
  ] as const) {
    const folder = join(directory, `scaffold-${filename}`);
    mkdirSync(join(folder, 'existing'), {recursive: true});
    writeFileSync(join(folder, filename), content);
    writeFileSync(join(folder, 'existing/morphir.toml'), "project.name='Existing'");
    const local = (args: string[]) => run(['--isolated', '--discovery-boundary', '.', ...args, '--json'], 0, folder);
    local(['project', 'add', 'new', '--name', 'New', '--language', 'scheme']);
    assert.equal(readFileSync(join(folder, filename), 'utf8'), content);
    assert.deepEqual(JSON.parse(local(['workspace']).stdout).projects.map((project: {name: string}) => project.name).sort(), ['Existing', 'New']);
    local(['project', 'remove', 'existing']);
    assert.deepEqual(JSON.parse(local(['workspace']).stdout).projects.map((project: {name: string}) => project.name), ['New']);
    assert.ok(existsSync(join(folder, 'existing/morphir.toml')));
  }

  for (const [filename, content] of [
    ['morphir.json', '{workspace:{members:[]},project:{name:"Lower"}}'],
    ['morphir.json5', '// keep\n{workspace:{members:[]},project:{name:"Lower"}}'],
    ['morphir.yaml', 'workspace:\n  members: []\nproject:\n  name: Lower\n'],
    ['morphir.yml', 'workspace:\n  members: []\nproject:\n  name: Lower\n'],
  ] as const) {
    for (const higher of [false, true]) {
      const folder = join(directory, `root-refusal-${filename}-${higher}`);
      mkdirSync(join(folder, 'src'), {recursive: true});
      writeFileSync(join(folder, filename), content);
      const toml = '# keep TOML\n[workspace]\nmembers=[]\n[project]\nname="Higher"\n';
      if (higher) writeFileSync(join(folder, 'morphir.toml'), toml);
      writeFileSync(join(folder, 'src/keep.scm'), '(define keep 1)');
      const result = run(['project', 'remove', '.', '--isolated', '--discovery-boundary', '.', '--json'], 2, folder);
      const failure = JSON.parse(result.stdout);
      assert.equal(failure.successful, false);
      assert.ok(failure.error.includes(filename), result.stdout);
      assert.ok(failure.error.includes('project declaration'), result.stdout);
      assert.equal(readFileSync(join(folder, filename), 'utf8'), content);
      assert.equal(readFileSync(join(folder, 'src/keep.scm'), 'utf8'), '(define keep 1)');
      assert.equal(existsSync(join(folder, 'morphir.toml')), higher);
      if (higher) assert.equal(readFileSync(join(folder, 'morphir.toml'), 'utf8'), toml);
      assert.equal(existsSync(join(folder, '.morphir-workspace-edit.lock')), false);
    }
  }

  const lowerWorkspace = join(directory, 'root-toml-lower-workspace');
  mkdirSync(join(lowerWorkspace, 'src'), {recursive: true});
  const lower = '{workspace:{members:[]}}';
  writeFileSync(join(lowerWorkspace, 'morphir.json'), lower);
  writeFileSync(join(lowerWorkspace, 'morphir.toml'), '# keep\n[project]\nname="Root"\n');
  writeFileSync(join(lowerWorkspace, 'src/keep.scm'), '(define keep 1)');
  const removedRoot = JSON.parse(run(['project', 'remove', '.', '--isolated', '--discovery-boundary', '.', '--json'], 0, lowerWorkspace).stdout);
  assert.equal(removedRoot.successful, true);
  assert.equal(readFileSync(join(lowerWorkspace, 'morphir.json'), 'utf8'), lower);
  assert.equal(readFileSync(join(lowerWorkspace, 'src/keep.scm'), 'utf8'), '(define keep 1)');
  assert.equal(JSON.parse(run(['workspace', '--isolated', '--discovery-boundary', '.', '--json'], 0, lowerWorkspace).stdout).projects.length, 0);
}
