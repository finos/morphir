import { Resvg } from '@resvg/resvg-js';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { isRecord } from '../../../types/data.ts';

const args = process.argv.slice(2);
if (args.length > 1 || args.some(argument => argument !== '--check')) throw new Error('Usage: build-icon.ts [--check]');
const source = new URL('../../morphir-workbench/assets/morphir-mark.svg', import.meta.url);
const output = new URL('../assets/morphir-icon.png', import.meta.url);
const receipt = new URL('../assets/morphir-icon.json', import.meta.url);
const original = readFileSync(source);
const svg = original.toString('utf8');
const viewBox = 'viewBox="0 0 163 184.4"';
if (svg.split(viewBox).length !== 2) throw new Error('Review the updated Morphir artwork before regenerating the package icon.');
// Center the existing paths and colors on a transparent square. No fonts or
// platform image utilities participate in the generated PNG.
const canvas = svg.replace(viewBox, 'width="512" height="512" viewBox="-46.5 -35.8 256 256"');
const rendered = new Resvg(canvas, { font: { loadSystemFonts: false } }).render();
if (rendered.width !== 512 || rendered.height !== 512) throw new Error('The package icon must be 512 by 512.');
const png = rendered.asPng();
const renderer: unknown = createRequire(import.meta.url)('@resvg/resvg-js/package.json');
if (!isRecord(renderer) || renderer.name !== '@resvg/resvg-js' || typeof renderer.version !== 'string') throw new Error('Missing renderer provenance.');
const sha256 = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const provenance = Buffer.from(JSON.stringify({ source: 'apps/morphir-workbench/assets/morphir-mark.svg',
  sourceSha256: sha256(original), renderer: `${renderer.name}@${renderer.version}`,
  width: rendered.width, height: rendered.height, systemFonts: false, pngSha256: sha256(png) }, null, 2) + '\n');
if (args[0] === '--check') {
  if (!readFileSync(output).equals(png) || !readFileSync(receipt).equals(provenance)) throw new Error('Package icon differs. Run bun --check apps/morphir-workbench-desktop/scripts/build-icon.ts.');
} else {
  mkdirSync(new URL('../assets/', import.meta.url), { recursive: true });
  writeFileSync(output, png); writeFileSync(receipt, provenance);
}
console.log(`Morphir package icon ${args[0] === '--check' ? 'verified' : 'generated'}: ${sha256(png)}`);
