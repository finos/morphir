import { checkedBuild } from '../../../tools/build.ts';
import { execFileSync } from 'node:child_process';
import {createHash} from 'node:crypto';
import { copyFileSync, cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const build = join(app, '_build');
const dist = join(app, 'dist');
const zipPackage = join(app, 'node_modules/@zip.js/zip.js');
const zipLicense = readFileSync(join(zipPackage, 'LICENSE'));
if (JSON.parse(readFileSync(join(zipPackage, 'package.json'), 'utf8')).version !== '2.24.0' ||
    createHash('sha256').update(zipLicense).digest('hex') !== '1b7ebc8d7889ed25491484ab2b102370742ca6c0b26650a0c62cc2269b579b84' ||
    !zipLicense.equals(readFileSync(join(app, 'licenses/zip.js-LICENSE.txt')))) {
  throw new Error('The pinned Workbench ZIP dependency or license has changed.');
}
// Retired bundles and failed earlier builds must not survive into packaged assets.
rmSync(dist, { recursive: true, force: true });
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build,
  ...['browser', 'worker', 'execution-host', 'execution-core'].map(name => join(app, name))], { cwd: app, stdio: 'inherit' });
mkdirSync(dist, { recursive: true });
mkdirSync(join(dist, 'licenses'), {recursive: true});
for (const name of ['zip.js-LICENSE.txt', 'zip.js-provenance.json']) {
  copyFileSync(join(app, 'licenses', name), join(dist, 'licenses', name));
}
// The MoonBit output keeps long mangled names, so the generated bundles are minified. bootstrap.js imports browser.js
// and execution-core.js as modules; transport.ts starts worker.js as a classic worker, so it stays a script (an IIFE).
const generated = (name: string) => join(build, 'js/release/build/finos/morphir-workbench', name, `${name}.js`);
for (const [name, format] of [['browser', 'esm'], ['execution-core', 'esm'], ['worker', 'iife']] as const) {
  const result = await Bun.build({ entrypoints: [generated(name)], outdir: dist, target: 'browser', format,
    minify: true, env: 'disable', throw: false, plugins: [{name: 'product-observer', setup(build) {
      build.onResolve({filter: /^@morphir\/moonbit-workbench\/product-observer$/}, () => ({path: './product-observer.js', external: true}));
    }}] });
  if (!result.success) throw new AggregateError(result.logs, `Minifying ${name}.js failed`);
}
for (const [source, name] of [
  ['index.html', 'index.html'], ['workbench.css', 'workbench.css'],
  ['browser/model-explorer/explorer.css', 'model-explorer.css'],
] as const) copyFileSync(join(app, source), join(dist, name));
// The controlled observed host serves this separate, source-bound template.
// Its fixed module attaches observation before starting the ordinary app. Refuse
// template drift instead of publishing a page that might start it twice.
const ordinaryEntry = '<script type="module" src="./bootstrap.js"></script>';
const index = readFileSync(join(app, 'index.html'), 'utf8');
if (index.split(ordinaryEntry).length !== 2) {
  throw new Error('The Workbench index must contain exactly one ordinary bootstrap entry.');
}
writeFileSync(join(dist, 'observed-index.html'), index.replace(ordinaryEntry,
  '<script type="module" src="./observed-document-entry.js"></script>'));
for (const name of ['bootstrap', 'observed-bootstrap', 'observed-document-entry', 'product-observer', 'transport', 'execution-session', 'execution-transport', 'native-session', 'native-workspace', 'artifact-download']) {
  await checkedBuild({ entrypoints: [join(app, 'browser', `${name}.ts`)], outdir: dist,
    plugins: [{ name: 'built-editor', setup(build) {
      build.onResolve({ filter: /^\.\/code-editor\.js$/ }, ({ path }) => ({ path, external: true }));
      if (name !== 'product-observer') build.onResolve({ filter: /(?:^|\/)product-observer\.(?:ts|js)$/ }, () => ({path: './product-observer.js', external: true}));
      if (name !== 'observed-bootstrap') build.onResolve({ filter: /(?:^|\/)observed-bootstrap\.(?:ts|js)$/ }, () => ({path: './observed-bootstrap.js', external: true}));
    } }],
    tsconfig: resolve(app, '../../tsconfig.browser.json') });
}
await checkedBuild({ entrypoints: [join(app, 'browser/editor/code-editor.ts')], outdir: dist, minify: true,
  tsconfig: resolve(app, '../../tsconfig.browser.json') });
console.log('Workbench built in apps/morphir-workbench/dist');

for (const name of readdirSync(join(app, 'assets'))) {
  if (name.endsWith(".svg")) copyFileSync(join(app, 'assets', name), join(dist, name));
}

cpSync(join(app, 'assets/samples'), join(dist, 'samples'), { recursive: true });
