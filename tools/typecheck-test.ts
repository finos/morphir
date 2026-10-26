import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';
import { checkedBuild } from './build.ts';

const root = fileURLToPath(new URL('../', import.meta.url));
// Check source coverage independently of imports, so a new isolated script cannot
// silently escape all four projects. Generated JavaScript is ignored by git;
// the pinned, unmodified Archify vendor package is not handwritten project code.
// docs/templates/assets/ holds browser assets that static HTML documents load with
// no build step: vendored highlight.js and its five-line setup script.
const inventory = Bun.spawnSync(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--',
  '*.ts', '*.mts', '*.cts', '*.js', '*.mjs', '*.cjs', ':(exclude).agents/skills/archify/**',
  ':(exclude)docs/templates/assets/**'], { cwd: root });
assert.equal(inventory.exitCode, 0, inventory.stderr.toString());
const sources = inventory.stdout.toString().trim().split(/\r?\n/).filter(Boolean);
assert.deepEqual(sources.filter(path => /\.(?:js|mjs|cjs)$/.test(path)), [], 'Handwritten JavaScript must be TypeScript');
const listed = Bun.spawnSync([process.execPath, 'check', '--all', '--listFilesOnly'], { cwd: root });
assert.equal(listed.exitCode, 0, listed.stderr.toString());
const normalize = (path: string) => resolve(path).replaceAll('\\', '/');
const covered = new Set(listed.stdout.toString().trim().split(/\r?\n/).map(normalize));
assert.deepEqual(sources.filter(path => !covered.has(normalize(join(root, path)))), [], 'Every source must belong to a checked project');
console.log(`${sources.length} handwritten TypeScript sources belong to checked projects`);
const projects = [
  ['browser', 'document.title', 'browser'],
  ['worker', 'self.location.href', 'browser'],
  ['node', 'process.version', 'node'],
  ['tooling', 'Bun.version', 'bun'],
] as const;
mkdirSync(join(root, '.dev'), { recursive: true });
const scratch = mkdtempSync(join(root, '.dev/typescript-gates-'));
const check = (project: string) => {
  const result = Bun.spawnSync([process.execPath, 'check', '-p', project], { cwd: root });
  return { code: result.exitCode, text: result.stdout.toString() + result.stderr.toString() };
};

try {
  for (const [name, available, target] of projects) {
    const project = join(scratch, `${name}.json`);
    const entry = join(scratch, `${name}.ts`);
    const sibling = join(scratch, `${name}-unimported.ts`);
    const output = join(scratch, `${name}-output`);
    writeFileSync(project, JSON.stringify({ extends: join(root, `tsconfig.${name}.json`),
      include: [entry, sibling], exclude: [],
    }));
    const valid = `export const environment = ${available};\nexport const value: string = 'checked';\n`;
    writeFileSync(entry, valid);
    writeFileSync(sibling, 'export const separate: string = 42;\n');
    const whole = check(project);
    assert.notEqual(whole.code, 0, `${name} must check unimported project files`);
    assert.match(whole.text, /TS2322/);

    writeFileSync(sibling, 'export const separate: string = "checked";\n');
    const positive = check(project);
    assert.equal(positive.code, 0, positive.text);
    if (name !== 'tooling') {
      writeFileSync(entry, valid + 'export const toolingLeak = Bun.version;\n');
      const isolated = check(project);
      assert.notEqual(isolated.code, 0, `${name} must not expose Bun runtime APIs`);
      assert.match(isolated.text, /Cannot find name 'Bun'/);
    }

    writeFileSync(entry, valid.replace("'checked'", '42'));
    const failed = await checkedBuild({ entrypoints: [entry], outdir: output, target, tsconfig: project, throw: false });
    assert.equal(failed.success, false, `${name} checked build must fail on type errors`);
    assert.ok(failed.logs.some(log => /TS2322/.test(log.message)));
    assert.ok(!existsSync(output) || readdirSync(output).length === 0, 'A failed checked build must publish no artifacts');

    writeFileSync(entry, valid);
    const built = await checkedBuild({ entrypoints: [entry], outdir: output, target, tsconfig: project });
    assert.equal(built.success, true);
    assert.ok(readFileSync(join(output, `${name}.js`), 'utf8').includes('checked'));
    console.log(`${name}: whole-project checks, environment types, failed-build cleanup and JavaScript emission passed`);
  }
} finally { rmSync(scratch, { recursive: true, force: true }); }
