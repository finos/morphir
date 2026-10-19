import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/** Capture build inputs in a dirty checkout, including tracked deletions.
 * Git's NUL-delimited inventory keeps unusual filenames unambiguous. */
export function sourceSnapshot(repo: string) {
  const files = execFileSync('git', ['ls-files', '-co', '--exclude-standard', '-z', '--',
    'apps/morphir', 'apps/morphir-workbench', 'pkgs', 'types', 'tools', 'moon.mod', 'moon.work'],
  { cwd: repo, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }).split('\0').filter(Boolean);
  const inventory = [...new Set(files)].sort().map(path => ({
    path, sha256: existsSync(join(repo, path))
      ? createHash('sha256').update(readFileSync(join(repo, path))).digest('hex') : null,
  }));
  return { sha256: createHash('sha256').update(JSON.stringify(inventory)).digest('hex'), inventory };
}
