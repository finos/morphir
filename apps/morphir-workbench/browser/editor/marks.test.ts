import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Text } from '@codemirror/state';
import type { DecorationSet } from '@codemirror/view';
import { markSet, position } from './marks.ts';

const doc = Text.of(['module A', '', 'bad =']);
const ranges = (set: DecorationSet) => { const found: [number, number][] = []; set.between(0, doc.length, (from, to) => { found.push([from, to]); }); return found; };
const mark = (line: number, column: number, endLine: number, endColumn: number) => JSON.stringify([{ line, column, endLine, endColumn, message: 'm' }]);

test('bad JSON and a non-array give no marks', () => {
  assert.deepEqual(ranges(markSet(doc, '{not json')), []);
  assert.deepEqual(ranges(markSet(doc, '{"line":1}')), []);
  assert.deepEqual(ranges(markSet(doc, '')), []);
});

test('positions beyond the document are clamped', () => {
  assert.equal(position(doc, 99, 99), doc.length);
  assert.equal(position(doc, 0, 0), 0);
  assert.equal(position(doc, 1, 99), 8);
});

test('a reversed range is swapped', () => {
  assert.deepEqual(ranges(markSet(doc, mark(3, 4, 3, 1))), [[10, 13]]);
});

test('an empty range widens to one character, or the previous one at a line end', () => {
  assert.deepEqual(ranges(markSet(doc, mark(3, 2, 3, 2))), [[11, 12]]);
  assert.deepEqual(ranges(markSet(doc, mark(3, 6, 3, 6))), [[14, 15]]);
});
