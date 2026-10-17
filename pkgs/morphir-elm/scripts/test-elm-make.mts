import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const modules = join(repository, 'pkgs/morphir-elm/scripts/node_modules');
// Node does not spawn `.cmd` files without a shell, so Windows uses the binary package directly.
const elm = process.platform === 'win32'
  ? join(modules, '@elm_binaries/win32_x64/elm.exe')
  : join(modules, '.bin/elm');
const nowhere = process.platform === 'win32' ? 'NUL' : '/dev/null';
const version = execFileSync(elm, ['--version'], { encoding: 'utf8' }).trim();
assert.equal(version, '0.19.1', `Elm must be 0.19.1, got ${version}`);

const output = JSON.parse(execFileSync('moon', ['run', 'pkgs/morphir-elm/acceptance', '--target', 'native'], {
  cwd: repository, encoding: 'utf8', maxBuffer: 16777216,
}));
assert.ok(output.projects.length >= 7, 'expected at least seven generated projects');

const workspace = mkdtempSync(join(tmpdir(), 'morphir-elm-'));
const failures = [];
try {
  for (const project of output.projects) {
    const root = join(workspace, project.name);
    for (const file of project.files) {
      const path = join(root, file.path);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, file.content);
    }
    const sources = project.files.filter((f: {path: string;content: string}) => f.path.endsWith('.elm')).map((f: {path: string;content: string}) => f.path);
    const result = spawnSync(elm, ['make', ...sources, `--output=${nowhere}`, '--report=json'], {
      cwd: root, encoding: 'utf8',
    });
    if (result.status !== 0) {
      failures.push(`${project.name}:\n${result.stderr || result.stdout}`);
    } else {
      console.log(`elm make accepted ${project.name} (${sources.length} modules)`);
    }
  }
} finally {
  rmSync(workspace, { recursive: true, force: true });
}
assert.deepEqual(failures, [], failures.join('\n\n'));
