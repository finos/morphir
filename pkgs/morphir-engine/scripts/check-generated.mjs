import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { includeDependencyPath } from '../../../apps/morphir/build-provider/paths.mjs';

// Runs an acceptance executable that prints generated MoonBit libraries and Elm projects, then checks them:
// `moon build` must accept each library (`moonbit`) and `elm make` each project (`elm`).
// Usage: node check-generated.mjs <moonbit|elm> [acceptance package, default pkgs/morphir-engine/acceptance/inference]
const backend = process.argv[2];
assert.ok(['moonbit', 'elm'].includes(backend), 'Supply the backend as an argument: moonbit or elm');
const acceptance = process.argv[3] ?? 'pkgs/morphir-engine/acceptance/inference';
const repository = fileURLToPath(new URL('../../../', import.meta.url));

function generate() {
  return JSON.parse(execFileSync('moon', ['run', acceptance, '--target', 'native'], {
    cwd: repository, encoding: 'utf8', maxBuffer: 16777216,
  }));
}

function checkElm(output) {
  const modules = join(repository, 'pkgs/morphir-elm/scripts/node_modules');
  // Node does not spawn `.cmd` files without a shell, so Windows uses the binary package directly.
  const elm = process.platform === 'win32'
    ? join(modules, '@elm_binaries/win32_x64/elm.exe')
    : join(modules, '.bin/elm');
  const nowhere = process.platform === 'win32' ? 'NUL' : '/dev/null';
  const version = execFileSync(elm, ['--version'], { encoding: 'utf8' }).trim();
  assert.equal(version, '0.19.1', `Elm must be 0.19.1, got ${version}`);
  assert.ok(output.elm.length > 0, 'expected generated Elm projects');
  const workspace = mkdtempSync(join(tmpdir(), 'morphir-generated-elm-'));
  const failures = [];
  try {
    for (const project of output.elm) {
      const root = join(workspace, project.name);
      for (const file of project.files) {
        const path = join(root, file.path);
        mkdirSync(dirname(path), { recursive: true });
        writeFileSync(path, file.content);
      }
      const sources = project.files.filter(f => f.path.endsWith('.elm')).map(f => f.path);
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
  for (const gap of output.elmGaps ?? []) {
    console.log(`known Elm gap ${gap.name}: ${gap.code} (${gap.detail})`);
  }
  assert.deepEqual(failures, [], failures.join('\n\n'));
}

function checkMoonBit(output) {
  // An explicit MOON_HOME wins; otherwise use the pinned toolchain that mise installs.
  const coreHome = process.env.MOON_HOME ||
    execFileSync('mise', ['where', 'http:moonbit'], { cwd: repository, encoding: 'utf8' }).trim();
  assert.ok(coreHome, 'Set MOON_HOME to the pinned compiler/core installation');
  const moon = join(coreHome, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
  const sdk = join(repository, 'pkgs/morphir-sdk');
  const excluded = new Set(['_build', '.mooncakes', '.git', 'node_modules']);
  assert.ok(output.moonbit.length > 0, 'expected generated MoonBit libraries');
  const failures = [];
  for (const library of output.moonbit) {
    const workspace = mkdtempSync(join(tmpdir(), 'morphir-generated-moonbit-'));
    try {
      cpSync(sdk, join(workspace, 'sdk'), { recursive: true, filter: path => includeDependencyPath(sdk, path, excluded) });
      const generated = join(workspace, 'generated');
      for (const artifact of library.artifacts) {
        const path = join(generated, artifact.path);
        mkdirSync(dirname(path), { recursive: true });
        writeFileSync(path, typeof artifact.content === 'string' ? artifact.content : Buffer.from(artifact.content));
      }
      writeFileSync(join(workspace, 'moon.work'), 'members=["./generated","./sdk"]\n');
      const result = spawnSync(moon, ['build', '--target', 'native'], {
        cwd: workspace,
        encoding: 'utf8',
        env: { ...process.env, MOON_HOME: coreHome },
      });
      if (result.status !== 0) {
        failures.push(`${library.name}:\n${result.stdout}${result.stderr}`);
      } else {
        console.log(`moon build accepted ${library.name}`);
      }
    } finally {
      rmSync(workspace, { recursive: true, force: true });
    }
  }
  for (const gap of output.moonbitGaps) {
    console.log(`known MoonBit gap ${gap.name}: ${gap.code}${gap.node ? ` at ${gap.node}` : ''} (${gap.detail})`);
  }
  assert.deepEqual(failures, [], failures.join('\n\n'));
}

const output = generate();
if (backend === 'elm') checkElm(output);
else checkMoonBit(output);
