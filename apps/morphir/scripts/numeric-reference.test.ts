import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertNumericReference } from './numeric-reference.ts';
import { bits, decimal, floating, integer } from './numeric-corpus.ts';

test('exact policy preserves signed zero and large integers and compares Decimal values', () => {
  assert.equal(Object.is(decimal('2').exponent,-0),false,'Decimal exponent is a canonical integer');
  assertNumericReference(integer('9007199254740993'), {kind:'exact',expected:integer('9007199254740993')}, 'large integer');
  assertNumericReference(decimal('12.3400'), {kind:'exact',expected:decimal('12.3400')}, 'native Decimal');
  assert.throws(() => assertNumericReference(floating(-0), {kind:'exact',expected:floating(0)}, 'signed zero'));
  assertNumericReference(decimal('12.34'), {kind:'exact',expected:decimal('12.3400')}, 'equivalent scale');
  assertNumericReference({type:'decimal',coefficient:'0',exponent:-32}, {kind:'exact',expected:decimal('0')}, 'classic underflow zero');
  assert.throws(() => assertNumericReference(decimal('12.3401'), {kind:'exact',expected:decimal('12.34')}, 'different value'));
  assert.throws(() => assertNumericReference({type:'decimal',coefficient:'1',exponent:-33}, {kind:'exact',expected:decimal('0')}, 'small nonzero is never zero'));
});

test('ULP policy orders both signs and refuses values outside the stated bound', () => {
  for (const expected of [1, -1]) {
    const reference = bits(expected);
    assertNumericReference({type:'float64',bits:(BigInt(reference)+4n).toString()}, {kind:'ulp',bits:reference,maxUlps:4}, 'boundary');
    assert.throws(() => assertNumericReference({type:'float64',bits:(BigInt(reference)+5n).toString()}, {kind:'ulp',bits:reference,maxUlps:4}, 'outside'));
  }
  assert.throws(() => assertNumericReference(floating(-0), {kind:'ulp',bits:bits(0),maxUlps:0}, 'zero'));
  assert.throws(() => assertNumericReference(floating(Infinity), {kind:'ulp',bits:bits(1),maxUlps:4}, 'infinite'));
  assert.throws(() => assertNumericReference(floating(NaN), {kind:'ulp',bits:bits(1),maxUlps:4}, 'NaN'));
});

test('NaN policy classifies payloads without inventing a payload contract', () => {
  for (const value of ['9221120237041090561','18444492273895866367']) {
    assertNumericReference({type:'float64',bits:value}, {kind:'category',category:'nan'}, 'NaN payload');
  }
  assert.throws(() => assertNumericReference(floating(Infinity), {kind:'category',category:'nan'}, 'infinity'));
  assertNumericReference(floating(Infinity), {kind:'category',category:'positive-infinity'}, 'positive infinity');
  assert.throws(() => assertNumericReference(floating(-Infinity), {kind:'category',category:'positive-infinity'}, 'negative infinity'));
});

test('binary64 comparison refuses malformed observations and invalid bounds', () => {
  for (const value of ['-1','1.0','18446744073709551616']) {
    assert.throws(() => assertNumericReference({type:'float64',bits:value}, {kind:'ulp',bits:bits(1),maxUlps:4}, 'invalid bits'));
  }
  assert.throws(() => assertNumericReference(floating(1), {kind:'ulp',bits:bits(1),maxUlps:-1}, 'invalid bound'));
});
