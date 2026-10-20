import assert from 'node:assert/strict';
import type { NumericModel, NumericResult, NumericRow, NumericValue } from './numeric-corpus.ts';

export interface NumericSymbol { fqname: string; function: string; public: boolean; }
type Fixed = 'Int32' | 'Int16' | 'Int64' | 'Byte' | 'UInt16' | 'UInt32' | 'UInt64';
const unwrap: Record<Fixed, string> = {
  Int32:'from_int32',Int16:'from_int16',Int64:'from_int64',Byte:'from_byte',
  UInt16:'from_uint16',UInt32:'from_uint32',UInt64:'from_uint64',
};
const quoted = (value: string) => JSON.stringify(value);
const identifier = (value: string) => { assert.match(value,/^[a-zA-Z_][a-zA-Z0-9_]*$/); return value; };
export const numericAliases = (id: string) => ({original:identifier('o_'+id),generated:identifier('g_'+id)});

function integerText(value: NumericValue): string {
  if (value.type === 'custom') {
    assert.equal(value.items.length,1);
    return integerText(value.items[0]!);
  }
  assert.ok(value.type === 'int');
  return value.value;
}

function assertion(row: NumericRow, call: string, kind: 'original' | 'generated'): string {
  const reference = row.reference;
  const result: NumericResult = row.result;
  const float = result === 'Float' && kind === 'original' ? `(${call}).to_double()` : call;
  if (reference.kind === 'category') {
    assert.ok(result === 'Float' || result === 'Double');
    return reference.category === 'nan' ? `assert_true((${float}).is_nan())`
      : `assert_eq((${float}).reinterpret_as_uint64(), 9218868437227405312UL)`;
  }
  if (reference.kind === 'ulp') {
    assert.ok(result === 'Float' || result === 'Double');
    return `assert_numeric_ulps(${float}, ${reference.bits}UL, ${reference.maxUlps}UL)`;
  }
  const expected = reference.expected;
  if (expected.type === 'model-error') {
    const errors: Record<string,string> = {
      'sdk.invalid_number':'@sdk.InvalidNumber(_)',
      'sdk.decimal.division_by_zero':'@decimal.DivisionByZero',
      'sdk.decimal.underflow':'@decimal.Underflow',
      'sdk.decimal.precision_loss':'@decimal.PrecisionLoss',
      'sdk.decimal.invalid_literal':'@decimal.InvalidLiteral',
    };
    assert.ok(Object.hasOwn(errors,expected.code), 'Unknown expected numeric model error');
    return `try { ignore(${call}); fail("Expected numeric model error") } catch { ${errors[expected.code]} => (); error => raise error }`;
  }
  switch (result) {
    case 'Bool':
      assert.ok(expected.type === 'bool');
      return `assert_eq(${call}, ${expected.value})`;
    case 'Float': case 'Double':
      assert.ok(expected.type === 'float64');
      return `assert_eq((${float}).reinterpret_as_uint64(), ${expected.bits}UL)`;
    case 'Decimal':
      assert.ok(expected.type === 'decimal' && reference.decimalText !== undefined);
      return `assert_eq(@decimal.to_string(${call}), ${quoted(reference.decimalText)})`;
    case 'Integer?': case 'Double?': {
      assert.ok(expected.type === 'maybe');
      const project = result === 'Integer?' ? '@integer.to_string' : 'value => value.reinterpret_as_uint64()';
      let wanted = 'None';
      if (expected.case === 'just') {
        if (result === 'Integer?') wanted = `Some(${quoted(integerText(expected.value))})`;
        else { assert.ok(expected.value.type === 'float64'); wanted = `Some(${expected.value.bits}UL)`; }
      }
      return `assert_eq((${call}).map(${project}), ${wanted})`;
    }
    case 'Integer':
      return `assert_eq(@integer.to_string(${call}), ${quoted(integerText(expected))})`;
    case 'BigInt':
      return `assert_eq(${kind === 'original' ? `(${call}).to_string()` : `@integer.to_string(${call})`}, ${quoted(integerText(expected))})`;
    default: {
      const project = kind === 'original' ? `(${call})${result === 'Byte' ? '.to_int()' : ''}.to_string()` : `@integer.to_string(@int.${unwrap[result]}(${call}))`;
      return `assert_eq(${project}, ${quoted(integerText(expected))})`;
    }
  }
}

// The binary64 sign mapping orders finite encodings, including both zero signs.
const ulpHelper = `///|
fn assert_numeric_ulps(value : Double, expected : UInt64, bound : UInt64) -> Unit raise {
  assert_true(!value.is_nan() && !value.is_inf())
  fn ordered(raw : UInt64) -> UInt64 {
    if (raw & 9223372036854775808UL) == 0UL {
      raw | 9223372036854775808UL
    } else { raw ^ 18446744073709551615UL }
  }
  let actual = ordered(value.reinterpret_as_uint64())
  let wanted = ordered(expected)
  let distance = if actual >= wanted { actual - wanted } else { wanted - actual }
  assert_true(distance <= bound)
}
`;

/** The shell supplies artifacts and symbols from the actual installed CLI. */
export function emitNumericConsumer(inputs: {model: NumericModel; symbols: NumericSymbol[]}[]): {source: string; tests: number} {
  const output = [ulpHelper];
  let tests = 0;
  for (const {model,symbols} of inputs) {
    const aliases = numericAliases(model.id);
    for (const row of model.rows) {
      const matches = symbols.filter(symbol => symbol.fqname.endsWith('#'+row.name));
      assert.equal(matches.length,1,'Exactly one generated symbol must identify '+row.name);
      const symbol = matches[0]!;
      assert.equal(symbol.public,true,'Numeric rows must use public source entries');
      for (const kind of ['original','generated'] as const) {
        const args = row.arguments.map(arg => kind === 'original' ? arg.source : arg.generated);
        const call = kind === 'original'
          ? `@${aliases.original}.${identifier(row.name.replaceAll('-','_'))}(${args.join(', ')})`
          : `@${aliases.generated}.${identifier(symbol.function)}()${args.map(arg=>'('+arg+')').join('')}`;
        output.push(`///|\ntest ${quoted(model.id+' '+kind+' '+row.id)} {\n  ${assertion(row,call,kind)}\n}\n`);
        tests++;
      }
    }
  }
  return {source:output.join('\n'),tests};
}
