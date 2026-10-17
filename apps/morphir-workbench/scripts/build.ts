import { checkedBuild } from '../../../tools/build.ts';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const build = fileURLToPath(new URL('../_build/', import.meta.url));
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build,
  `${app}browser`, `${app}worker`, `${app}job-host`, `${app}job-core`], { cwd: app, stdio: 'inherit' });
mkdirSync(new URL('../dist/', import.meta.url), { recursive: true });
for (const name of ['browser', 'worker', 'job-core']) {
  copyFileSync(`${build}/js/release/build/finos/morphir-workbench/${name}/${name}.js`, `${app}/dist/${name}.js`);
}
for (const [source, name] of [
  ['index.html', 'index.html'], ['workbench.css', 'workbench.css'],
  ['browser/model-explorer/explorer.css', 'model-explorer.css'],
]) copyFileSync(`${app}/${source}`, `${app}/dist/${name}`);
for (const name of ['bootstrap', 'transport', 'job-session', 'job-transport', 'native-session', 'native-workspace', 'artifact-download']) {
  await checkedBuild({ entrypoints: [`${app}/browser/${name}.ts`], outdir: `${app}/dist`,
    plugins: [{ name: 'built-editor', setup(build) {
      build.onResolve({ filter: /^\.\/code-editor\.js$/ }, ({ path }) => ({ path, external: true }));
    } }],
    tsconfig: `${app}/../../tsconfig.browser.json` });
}
await checkedBuild({ entrypoints: [`${app}/browser/editor/code-editor.ts`], outdir: `${app}/dist`, minify: true,
  tsconfig: `${app}/../../tsconfig.browser.json` });
console.log('Workbench built in apps/morphir-workbench/dist');

for (const name of readdirSync(`${app}/assets`)) {
  if (name.endsWith(".svg")) copyFileSync(`${app}/assets/${name}`, `${app}/dist/${name}`);
}
