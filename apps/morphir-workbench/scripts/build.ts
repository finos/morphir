import { checkedBuild } from '../../../tools/build.ts';
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const build = join(app, '_build');
const dist = join(app, 'dist');
// Retired bundles and failed earlier builds must not survive into packaged assets.
rmSync(dist, { recursive: true, force: true });
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build,
  ...['browser', 'worker', 'execution-host', 'execution-core'].map(name => join(app, name))], { cwd: app, stdio: 'inherit' });
mkdirSync(dist, { recursive: true });
// The MoonBit output keeps long mangled names, so the generated bundles are minified. bootstrap.js imports browser.js
// and execution-core.js as modules; transport.ts starts worker.js as a classic worker, so it stays a script (an IIFE).
const generated = (name: string) => join(build, 'js/release/build/finos/morphir-workbench', name, `${name}.js`);
for (const [name, format] of [['browser', 'esm'], ['execution-core', 'esm'], ['worker', 'iife']] as const) {
  const result = await Bun.build({ entrypoints: [generated(name)], outdir: dist, target: 'browser', format,
    minify: true, env: 'disable', throw: false });
  if (!result.success) throw new AggregateError(result.logs, `Minifying ${name}.js failed`);
}
for (const [source, name] of [
  ['index.html', 'index.html'], ['workbench.css', 'workbench.css'],
  ['browser/model-explorer/explorer.css', 'model-explorer.css'],
] as const) copyFileSync(join(app, source), join(dist, name));
for (const name of ['bootstrap', 'transport', 'execution-session', 'execution-transport', 'native-session', 'native-workspace', 'artifact-download']) {
  await checkedBuild({ entrypoints: [join(app, 'browser', `${name}.ts`)], outdir: dist,
    plugins: [{ name: 'built-editor', setup(build) {
      build.onResolve({ filter: /^\.\/code-editor\.js$/ }, ({ path }) => ({ path, external: true }));
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
