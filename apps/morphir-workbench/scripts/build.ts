import { checkedBuild } from '../../../tools/build.ts';
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const build = fileURLToPath(new URL('../_build/', import.meta.url));
// Retired bundles and failed earlier builds must not survive into packaged assets.
rmSync(new URL('../dist/', import.meta.url), { recursive: true, force: true });
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build,
  `${app}browser`, `${app}worker`, `${app}execution-host`, `${app}execution-core`], { cwd: app, stdio: 'inherit' });
mkdirSync(new URL('../dist/', import.meta.url), { recursive: true });
// The MoonBit output keeps long mangled names, so the generated bundles are minified. bootstrap.js imports browser.js
// and execution-core.js as modules; transport.ts starts worker.js as a classic worker, so it stays a script (an IIFE).
const generated = (name: string) => `${build}/js/release/build/finos/morphir-workbench/${name}/${name}.js`;
for (const [name, format] of [['browser', 'esm'], ['execution-core', 'esm'], ['worker', 'iife']] as const) {
  const result = await Bun.build({ entrypoints: [generated(name)], outdir: `${app}/dist`, target: 'browser', format,
    minify: true, env: 'disable', throw: false });
  if (!result.success) throw new AggregateError(result.logs, `Minifying ${name}.js failed`);
}
for (const [source, name] of [
  ['index.html', 'index.html'], ['workbench.css', 'workbench.css'],
  ['browser/model-explorer/explorer.css', 'model-explorer.css'],
]) copyFileSync(`${app}/${source}`, `${app}/dist/${name}`);
for (const name of ['bootstrap', 'transport', 'execution-session', 'execution-transport', 'native-session', 'native-workspace', 'artifact-download']) {
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

cpSync(`${app}/assets/samples`, `${app}/dist/samples`, { recursive: true });
