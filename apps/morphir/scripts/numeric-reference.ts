import assert from 'node:assert/strict';
import type { NumericValue, Reference } from './numeric-corpus.ts';

const sign = 1n << 63n;
const mask = (1n << 64n) - 1n;
const exponent = 0x7ff0000000000000n;
const fraction = 0x000fffffffffffffn;

function binary64(value: string): bigint {
  assert.match(value, /^(0|[1-9][0-9]{0,19})$/, 'Canonical unsigned binary64 bits required');
  const result = BigInt(value);
  assert.ok(result <= mask, 'Binary64 bits exceed 64 bits');
  return result;
}

function ordered(value: bigint): bigint {
  return (value & sign) === 0n ? value | sign : value ^ mask;
}

function decimalValue(value: Extract<NumericValue,{type:'decimal'}>): [string,number] {
  assert.match(value.coefficient,/^-?\d+$/);
  assert.ok(Number.isSafeInteger(value.exponent),'Integral Decimal exponent required');
  let coefficient=BigInt(value.coefficient),exponent=value.exponent;
  if(coefficient===0n)return ['0',0];
  while(coefficient%10n===0n) { coefficient/=10n; exponent++; }
  return [coefficient.toString(),exponent];
}

/** Compare observations to authored expectations, never to another evaluator. */
export function assertNumericReference(actual: NumericValue, reference: Reference, label: string): void {
  if (reference.kind === 'exact') {
    // Exact model-value comparison follows the documented Decimal numerical
    // contract. Native receipt replay separately preserves each observed quantum.
    if(actual.type==='decimal'&&reference.expected.type==='decimal') {
      assert.deepEqual(decimalValue(actual),decimalValue(reference.expected),label);
    } else assert.deepEqual(actual, reference.expected, label);
    return;
  }
  assert.equal(actual.type, 'float64', label + ': expected a binary64 carrier');
  assert.ok(actual.type === 'float64');
  const observed = binary64(actual.bits);
  if (reference.kind === 'category') {
    if (reference.category === 'nan') {
      assert.ok((observed & exponent) === exponent && (observed & fraction) !== 0n, label + ': expected NaN');
    } else {
      assert.equal(observed, exponent, label + ': expected positive infinity');
    }
    return;
  }
  assert.ok(Number.isSafeInteger(reference.maxUlps) && reference.maxUlps >= 0, 'Nonnegative integer ULP bound required');
  const expected = binary64(reference.bits);
  assert.ok((observed & exponent) !== exponent && (expected & exponent) !== exponent, label + ': ULP comparisons require finite values');
  const a = ordered(observed), b = ordered(expected);
  const distance = a >= b ? a - b : b - a;
  assert.ok(distance <= BigInt(reference.maxUlps), `${label}: ${distance} ULPs exceeds ${reference.maxUlps}`);
}
