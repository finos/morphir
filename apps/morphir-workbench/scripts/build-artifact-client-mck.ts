import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { rmSync } from 'node:fs';
import { checkedBuild } from '../../../tools/build.ts';

const app = fileURLToPath(new URL('../', import.meta.url));
const root = new URL('../../../', import.meta.url);
execFileSync('moon', ['build', app + 'mck/json-frame', '--target', 'js', '--target-dir', app + '_build', '--release'], { cwd: app, stdio: 'inherit' });
const outdir = app + '_build/artifact-client-mck';
rmSync(outdir, { recursive: true, force: true });
const browser = await checkedBuild({ entrypoints: [app + 'browser/artifact-client-trace.ts'], outdir, target: 'browser',
  tsconfig: fileURLToPath(new URL('tsconfig.browser.json', root)) });
if (!browser.success) throw new AggregateError(browser.logs, 'Artifact browser trace build failed.');
const adapter = await checkedBuild({ entrypoints: [app + 'scripts/artifact-client-mck.ts'], outdir, target: 'node', naming: '[name].mjs', external: ['playwright'],
  tsconfig: fileURLToPath(new URL('tsconfig.node.json', root)) });
if (!adapter.success) throw new AggregateError(adapter.logs, 'Artifact adapter build failed.');
console.log('Checked artifact client adapter, browser trace and duplicate-aware framing codec built.');
