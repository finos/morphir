import { buildSync } from 'esbuild';
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
  ['browser/bootstrap.js', 'bootstrap.js'], ['browser/transport.js', 'transport.js'],
  ['browser/job-session.js', 'job-session.js'],
  ['browser/job-transport.js', 'job-transport.js'], ['browser/native-session.js', 'native-session.js'],
  ['browser/native-workspace.js', 'native-workspace.js'],
]) copyFileSync(`${app}/${source}`, `${app}/dist/${name}`);
buildSync({ entryPoints: [`${app}/browser/editor/code-editor.js`], outfile: `${app}/dist/code-editor.js`, bundle: true, format: 'esm', target: 'es2022', minify: true, legalComments: 'eof' });
buildSync({ entryPoints: [`${app}/browser/artifact-download.js`], outfile: `${app}/dist/artifact-download.js`, bundle: true, format: 'esm', target: 'es2022', minify: true, legalComments: 'eof' });
console.log('Workbench built in apps/morphir-workbench/dist');

for (const name of readdirSync(`${app}/assets`)) {
  if (name.endsWith(".svg")) copyFileSync(`${app}/assets/${name}`, `${app}/dist/${name}`);
}
