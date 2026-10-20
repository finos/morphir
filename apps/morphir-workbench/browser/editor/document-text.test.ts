import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DocumentText } from './document-text.ts';

const opened = (value: string, key: string) => { const text = new DocumentText(); text.render(value); text.open(key); return text; };

test('a new document starts from the rendered value', () => {
  const text = new DocumentText();
  text.render('(+ 1 2)');
  assert.equal(text.open('scheme'), '(+ 1 2)');
  assert.equal(text.key, 'scheme');
});

test('an edit stays with its document when the key changes in the same render', () => {
  // The render changes the key but not the value, so Rabbita does not set the value property again.
  const text = opened('', 'scheme');
  text.edit('(total 3)');
  assert.equal(text.open('gleam'), '', 'The Gleam document gets its rendered value, not the Scheme edit');
  assert.equal(text.current, '');
});

test('a new rendered value for the new document replaces the edit', () => {
  const text = opened('(+ 1 2)', 'scheme');
  text.edit('(total 3)');
  text.render('// gleam');
  assert.equal(text.open('gleam'), '// gleam');
});

test('an edit in the same document stays until the host renders a value', () => {
  const text = opened('(+ 1 2)', 'scheme');
  text.edit('(total 3)');
  assert.equal(text.open('scheme'), '(total 3)', 'The same key keeps the unrendered edit');
  assert.equal(text.current, '(total 3)');
  text.render('(total 4)');
  assert.equal(text.current, '(total 4)', 'A rendered value replaces the text of the current document');
});

test('returning to a document uses the value the host renders for it', () => {
  const text = opened('(+ 1 2)', 'scheme');
  text.edit('(total 3)');
  text.render('(total 3)');
  text.render('');
  assert.equal(text.open('gleam'), '');
  text.edit('// draft');
  text.render('(total 3)');
  assert.equal(text.open('scheme'), '(total 3)');
});
