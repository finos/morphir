import { buildSync } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { highlightDir } from './highlight.js';
import { withSiteHome } from './try-page.js';

const app = fileURLToPath(new URL('../', import.meta.url));
const root = fileURLToPath(new URL('../../../', import.meta.url));
const out = process.env.SITE_OUT ?? `${root}_site`;
const build = `${app}_build`;
const main = process.env.SITE_MAIN === '1';

rmSync(out, { recursive: true, force: true });

// 1. Islands (JS target), minified into _site/assets/islands.js.
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build, 'islands'], { cwd: app, stdio: 'inherit' });
mkdirSync(`${out}/assets`, { recursive: true });
buildSync({
  entryPoints: [`${build}/js/release/build/finos/morphir-site/islands/islands.js`],
  outfile: `${out}/assets/islands.js`,
  minify: true, format: 'esm', target: 'es2022', legalComments: 'eof',
});
const islandsSize = gzipSync(readFileSync(`${out}/assets/islands.js`)).length;
if (islandsSize > 25 * 1024) console.warn(`warning: assets/islands.js is ${islandsSize} bytes gzip, above the 25 KB target`);

// 2. Pages, feed, search index and static assets (native target).
const args = ['run', '--target', 'native', '--release', '--target-dir', build, 'generate', '--', '--root', root, '--out', out];
if (main) args.push('--main');
execFileSync('moon', args, { cwd: app, stdio: 'inherit' });

// 3. Code highlighting.
for (const w of await highlightDir(out)) console.warn(`warning: ${w}`);

// Client Mermaid fallback, loaded only by pages that need it.
copyFileSync(`${app}node_modules/mermaid/dist/mermaid.min.js`, `${out}/assets/mermaid.min.js`);

// 4. Workbench at /try/. It is served below a path, so its asset paths must be relative.
execFileSync('node', [`${root}apps/morphir-workbench/scripts/build.js`], { cwd: root, stdio: 'inherit' });
const workbench = `${root}apps/morphir-workbench/dist`;
if (!existsSync(`${workbench}/index.html`)) {
  console.error(`error: ${workbench}/index.html is missing; the workbench build did not produce dist/`);
  process.exit(1);
}
const index = readFileSync(`${workbench}/index.html`, 'utf8');
if (/(?:src|href)="\//.test(index)) {
  console.error('error: apps/morphir-workbench/dist/index.html uses an absolute asset path; /try/ needs relative paths');
  process.exit(1);
}
cpSync(workbench, `${out}/try`, { recursive: true });
writeFileSync(`${out}/try/index.html`, withSiteHome(index, '../'));
console.log(`site: built ${out}`);
