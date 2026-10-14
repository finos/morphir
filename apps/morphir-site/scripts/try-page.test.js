import { test } from 'node:test';
import assert from 'node:assert/strict';
import { withSiteHome } from './try-page.js';

test('the workbench page gets a site home meta tag before </head>', () => {
  const html = '<html><head><title>W</title></head><body></body></html>';
  assert.equal(withSiteHome(html, '../'),
    '<html><head><title>W</title><meta name="morphir-site-home" content="../"></head><body></body></html>');
});

test('a page without </head> is an error', () => {
  assert.throws(() => withSiteHome('<html><body></body></html>', '../'), /no <\/head>/);
});
