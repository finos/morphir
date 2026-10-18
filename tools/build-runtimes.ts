import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { checkedBuild } from './build.ts';

const root = new URL('../', import.meta.url);
// These paths are part of the installed CLI/host contract. Emit adjacent .mjs
// files so import.meta.url, worker URLs and runtime identity pins retain meaning.
for (const directory of ['apps/morphir/build-provider/', 'pkgs/morphir-host/runners/', 'pkgs/morphir-host/embedding/']) {
  const base = new URL(directory, root);
  for (const name of readdirSync(base)) {
    if (!name.endsWith('.mts') || name.endsWith('.d.mts') || name.startsWith('test-') || name === 'build.mts' || name === 'browser-worker.mts') continue;
    await checkedBuild({ entrypoints: [fileURLToPath(new URL(name, base))], outdir: fileURLToPath(base),
      target: directory.includes('embedding') && !name.startsWith('node') ? 'browser' : 'node',
      naming: '[name].mjs', external: ['./*.mjs', '../dist/*'], tsconfig: fileURLToPath(new URL('../tsconfig.node.json', import.meta.url)),
    });
  }
}
await checkedBuild({ entrypoints: [fileURLToPath(new URL('apps/morphir/bin/morphir.ts', root))],
  outdir: fileURLToPath(new URL('apps/morphir/bin/', root)), target: 'node', plugins: [{ name: 'compiled-cli', setup(build) {
    build.onResolve({ filter: /\/dist\/morphir\.js$/ }, ({ path }) => ({ path, external: true }));
  } }],
  tsconfig: fileURLToPath(new URL('../tsconfig.node.json', import.meta.url)),
});
