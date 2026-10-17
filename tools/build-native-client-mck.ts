import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { checkedBuild } from './build.ts';
const root = new URL('../', import.meta.url);
const app = fileURLToPath(new URL('apps/morphir-workbench/', root));
const out = app + '_build/native-client-mck';
execFileSync(
  'moon',
  [
    'build',
    app + 'worker',
    '--target',
    'js',
    '--release',
    '--target-dir',
    app + '_build',
  ],
  { cwd: app, stdio: 'inherit' },
);
for (const mode of ['debug', 'release'])
  execFileSync(
    'moon',
    [
      'build',
      app + 'job-core',
      '--target',
      'js',
      '--target-dir',
      app + '_build',
      ...(mode === 'release' ? ['--release'] : []),
    ],
    { cwd: app, stdio: 'inherit' },
  );
await checkedBuild({
  entrypoints: [app + 'browser/native-client-trace.ts'],
  outdir: out,
  target: 'browser',
  tsconfig: fileURLToPath(new URL('tsconfig.browser.json', root)),
});
await checkedBuild({
  entrypoints: [app + 'scripts/native-client-mck.ts'],
  outdir: out,
  target: 'node',
  naming: '[name].mjs',
  external: ['playwright'],
  tsconfig: fileURLToPath(new URL('tsconfig.node.json', root)),
});
console.log(
  'Checked native client MCK adapter and browser driver built with debug/release production cores',
);
