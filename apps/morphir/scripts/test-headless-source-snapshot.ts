import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { sourceSnapshot } from './headless-source-snapshot.ts';

test('source evidence retains tracked deletions, dirty/untracked inputs and unusual names', () => {
  const repo = mkdtempSync(join(tmpdir(), 'morphir-source-snapshot-'));
  try {
    execFileSync('git', ['init', '--quiet'], { cwd: repo });
    mkdirSync(join(repo, 'apps/morphir'), { recursive: true });
    const removed = 'apps/morphir/deleted.mbt';
    writeFileSync(join(repo, removed), 'tracked before deletion');
    // Only this disposable repository's index is populated; no commit is made.
    execFileSync('git', ['add', '--', removed], { cwd: repo });
    rmSync(join(repo, removed));
    const unusual = 'apps/morphir/untracked\ninput.mbt';
    writeFileSync(join(repo, unusual), 'captured input');
    writeFileSync(join(repo, '.gitignore'), 'apps/morphir/generated.js\n');
    writeFileSync(join(repo, 'apps/morphir/generated.js'), 'ignored build output');
    const before = sourceSnapshot(repo);
    assert.deepEqual(before.inventory, [
      { path: removed, sha256: null },
      { path: unusual, sha256: createHash('sha256').update('captured input').digest('hex') },
    ]);
    assert.deepEqual(sourceSnapshot(repo), before);
    writeFileSync(join(repo, unusual), 'edited during qualification');
    assert.notEqual(sourceSnapshot(repo).sha256, before.sha256);
    writeFileSync(join(repo, unusual), 'captured input');
    assert.equal(sourceSnapshot(repo).sha256, before.sha256);
    writeFileSync(join(repo, removed), 'restored tracked input');
    assert.notEqual(sourceSnapshot(repo).sha256, before.sha256);
  } finally { rmSync(repo, { recursive: true, force: true }); }
});
