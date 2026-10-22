import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

test('actual Workbench distribution ships the full pinned ZIP license and package provenance', () => {
  const license = readFileSync(new URL('../dist/licenses/zip.js-LICENSE.txt', import.meta.url));
  assert.equal(createHash('sha256').update(license).digest('hex'), '1b7ebc8d7889ed25491484ab2b102370742ca6c0b26650a0c62cc2269b579b84');
  assert.deepEqual(license, readFileSync(new URL('../licenses/zip.js-LICENSE.txt', import.meta.url)));
  const provenance = JSON.parse(readFileSync(new URL('../dist/licenses/zip.js-provenance.json', import.meta.url), 'utf8'));
  assert.equal(provenance.name, '@zip.js/zip.js');
  assert.equal(provenance.version, '2.24.0');
  assert.equal(provenance.license, 'BSD-3-Clause');
  assert.equal(provenance.integrity, 'sha512-WlaVKzdqBK+RF3bdiXZWbdCnvGB6PdO4IHC1mn/2Yfl3bASgqUNegnU3+PNg61iecwoPfUi5BgLUPqBukXpyWw==');
  assert.deepEqual(readFileSync(new URL('../dist/licenses/zip.js-provenance.json', import.meta.url)), readFileSync(new URL('../licenses/zip.js-provenance.json', import.meta.url)));
});
