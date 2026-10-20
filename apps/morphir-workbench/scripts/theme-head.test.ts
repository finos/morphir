import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// The head script of index.html applies a saved theme before the first paint. It must agree with the MoonBit
// decoder in browser/settings, so this test runs it on the saved values that the decoder's tests use.
const app = new URL('..', import.meta.url);
const html = readFileSync(new URL('index.html', app), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]!).find(s => s.includes('morphir-workbench.settings.v1'));
const decoderTests = readFileSync(new URL('browser/settings/settings_test.mbt', app), 'utf8');
const block = decoderTests.match(/let saved_cases[^=]*= \[([\s\S]*?)\n\]/)?.[1] ?? '';
const cases = [...block.matchAll(/\(("(?:[^"\\]|\\.)*"), (System|Light|Dark)\)/g)]
  .map(m => ({ saved: JSON.parse(m[1]!) as string, theme: m[2]! }));

// The `data-theme` that the head script sets when storage holds `saved`; `null` stands for an empty key.
function headTheme(saved: string | null): string | undefined {
  const dataset: Record<string, string> = {};
  const localStorage = { getItem: (key: string) => key === 'morphir-workbench.settings.v1' ? saved : null };
  runInNewContext(script!, { localStorage, document: { documentElement: { dataset } }, JSON });
  return dataset.theme;
}

test('index.html has the head script before its stylesheets', () => {
  assert.ok(script, 'the head script reads morphir-workbench.settings.v1');
  assert.ok(html.indexOf(script!) < html.indexOf('workbench.css'), 'the script runs before the stylesheet loads');
  assert.match(html, /<meta name="color-scheme" content="light dark">/);
});

test('the head script and the MoonBit decoder give the same theme for each saved value', () => {
  assert.ok(cases.length >= 10, `read ${cases.length} cases from settings_test.mbt`);
  for (const { saved, theme } of cases) {
    const expected = theme === 'System' ? undefined : theme.toLowerCase();
    assert.equal(headTheme(saved === '' ? null : saved), expected, `saved ${JSON.stringify(saved)}`);
  }
});

test('the head script never throws when storage is unavailable', () => {
  const dataset: Record<string, string> = {};
  const localStorage = { getItem: () => { throw new Error('blocked'); } };
  assert.doesNotThrow(() => runInNewContext(script!, { localStorage, document: { documentElement: { dataset } }, JSON }));
  assert.equal(dataset.theme, undefined);
});
