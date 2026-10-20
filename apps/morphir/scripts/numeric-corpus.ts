import assert from 'node:assert/strict';

export type NumericValue =
  | { type: 'int'; value: string }
  | { type: 'bool'; value: boolean }
  | { type: 'float64'; bits: string }
  | { type: 'decimal'; coefficient: string; exponent: number }
  | { type: 'text'; units: number[] }
  | { type: 'custom'; owner: string; tag: string; items: NumericValue[] }
  | { type: 'maybe'; case: 'nothing' }
  | { type: 'maybe'; case: 'just'; value: NumericValue }
  | { type: 'model-error'; code: string };

export type NumericResult = 'Bool' | 'Int32' | 'Int16' | 'Int64' | 'Byte' | 'UInt16' | 'UInt32' | 'UInt64'
  | 'BigInt' | 'Float' | 'Double' | 'Integer' | 'Decimal' | 'Integer?' | 'Double?';
export type Reference =
  | { kind: 'exact'; expected: NumericValue; decimalText?: string }
  | { kind: 'ulp'; bits: string; maxUlps: number }
  | { kind: 'category'; category: 'nan' | 'positive-infinity' };
export interface NumericArgument { value: NumericValue; source: string; generated: string; }
export interface NumericRow {
  id: string; name: string; result: NumericResult; arguments: NumericArgument[]; reference: Reference;
}
export const numericSourceProfile = 'moonbit-model-experimental-v1' as const;
export interface TypedNumericModel {
  profile: string; id: string; source: string; sourceEntries: string[]; irOnlyEntries: string[];
  mathReferences: { name: string; expected: number; ulps: number }[];
  mathCategories: { name: string; category: 'nan' | 'positive-infinity' }[];
  decimalReferences: { name: string; args: string[]; expected: string }[];
  decimalComparisons: { name: string; a: string; b: string; expected: boolean }[];
  decimalFailures: { name: string; args: string[]; code: string }[];
}
export interface NumericModel { profile: typeof numericSourceProfile; id: string; source: string; entries: string[]; rows: NumericRow[]; }

// Opaque type owners and constructor transport tags are distinct SDK contracts.
const boundaries = {
  Int32:{owner:'int-32',tag:'int32'},Int16:{owner:'int-16',tag:'int16'},Int64:{owner:'int-64',tag:'int64'},
  Byte:{owner:'byte',tag:'byte'},UInt16:{owner:'uint-16',tag:'uint-16'},
  UInt32:{owner:'uint-32',tag:'uint-32'},UInt64:{owner:'uint-64',tag:'uint-64'},
} as const;
export const numericModelIds = ['foundation', 'numeric', 'integer', 'float', 'math', 'conversions', 'decimal'] as const;

/** Encode authored binary64 references. This performs no model arithmetic. */
export function bits(value: number): string {
  const bytes = new DataView(new ArrayBuffer(8)); bytes.setFloat64(0, value, false);
  return bytes.getBigUint64(0, false).toString();
}
export function floating(value: number): NumericValue { return { type: 'float64', bits: bits(value) }; }
export function integer(value: string): NumericValue { assert.match(value, /^-?\d+$/); return { type: 'int', value }; }
export function wrapped(type: keyof typeof boundaries, value: string): NumericValue {
  const boundary = boundaries[type];
  return { type: 'custom', owner: 'morphir/SDK:int#' + boundary.owner, tag: 'morphir/SDK:int#' + boundary.tag, items: [integer(value)] };
}
export function decimal(text: string): Extract<NumericValue,{type:'decimal'}> {
  assert.match(text, /^-?\d+(?:\.\d+)?$/);
  const fraction = text.split('.')[1] ?? '';
  return { type: 'decimal', coefficient: BigInt(text.replace('.', '')).toString(), exponent: fraction.length === 0 ? 0 : -fraction.length };
}
const exact = (expected: NumericValue): Reference => ({ kind: 'exact', expected });
const decimalReference = (text: string): Reference => ({ kind: 'exact', expected: decimal(text), decimalText: text });
const nothing = (): NumericValue => ({ type: 'maybe', case: 'nothing' });
const just = (value: NumericValue): NumericValue => ({ type: 'maybe', case: 'just', value });
const bool = (value: boolean): NumericValue => ({ type: 'bool', value });
export const argBool = (value: boolean): NumericArgument => ({ value: bool(value), source: String(value), generated: String(value) });
export const argInt32 = (value: string): NumericArgument => ({
  value: wrapped('Int32', value), source: `(${value} : Int32)`,
  generated: `@int.to_int32(@integer.parse(${JSON.stringify(value)})).unwrap()`,
});
export const argInteger = (value: string): NumericArgument => ({
  value: integer(value), source: `@integer.parse(${JSON.stringify(value)})`, generated: `@integer.parse(${JSON.stringify(value)})`,
});
export const argDouble = (value: number, float32 = false): NumericArgument => {
  const expression = `(${bits(value)}UL).reinterpret_as_double()`;
  return { value: floating(value), source: float32 ? `Float::from_double(${expression})` : expression, generated: expression };
};
export const argText = (value: string): NumericArgument => ({
  value: { type: 'text', units: Array.from({ length: value.length }, (_, i) => value.charCodeAt(i)) },
  source: JSON.stringify(value), generated: `@sdk.Text::from_string(${JSON.stringify(value)})`,
});
const argMaybeInteger = (value: string | null): NumericArgument => ({
  value: value === null ? nothing() : just(integer(value)),
  source: value === null ? 'None' : `Some(@integer.parse(${JSON.stringify(value)}))`,
  generated: value === null ? 'None' : `Some(@integer.parse(${JSON.stringify(value)}))`,
});
const argDecimal = (value: string): NumericArgument => ({
  value: decimal(value), source: `@decimal.from_string_exact(${JSON.stringify(value)})`,
  generated: `@decimal.from_string_exact(${JSON.stringify(value)})`,
});

function rowsFor(model: TypedNumericModel): NumericRow[] {
  const rows: NumericRow[] = [];
  const add = (name: string, result: NumericResult, args: NumericArgument[], reference: Reference) => {
    rows.push({ id: name + '-' + rows.length, name, result, arguments: args, reference });
  };
  switch (model.id) {
    case 'foundation':
      for (const flag of [false, true]) add('choose', 'Int32', [argBool(flag), argInt32('-2147483648'), argInt32('2147483647')], exact(wrapped('Int32', flag ? '-2147483648' : '2147483647')));
      break;
    case 'numeric':
      for (const [name, expected] of [['overflow', '-2147483648'], ['underflow', '2147483647'], ['multiply-wrap', '0']] as const) add(name, 'Int32', [], exact(wrapped('Int32', expected)));
      add('total', 'Int32', [argInt32('3'), argInt32('400')], exact(wrapped('Int32', '1100')));
      add('total', 'Int32', [argInt32('3'), argInt32('4')], exact(wrapped('Int32', '12')));
      for (const [name, a, b, expected] of [['before', '-1', '1', true], ['before', '1', '-1', false], ['after', '1', '-1', true], ['same', '2', '2', true], ['same', '2', '3', false]] as const) add(name, 'Bool', [argInt32(a), argInt32(b)], exact(bool(expected)));
      break;
    case 'integer':
      for (const [name, type, expected] of [['wrap-i16', 'Int16', '-32768'], ['wrap-i64', 'Int64', '-9223372036854775808'], ['wrap-byte', 'Byte', '0'], ['wrap-u16', 'UInt16', '0'], ['wrap-u32', 'UInt32', '0'], ['wrap-u64', 'UInt64', '0']] as const) add(name, type, [], exact(wrapped(type, expected)));
      add('grow', 'BigInt', [], exact(integer('18446744073709551617')));
      break;
    case 'float':
      for (const [name, expected] of [['rounded', 16777216], ['chained', 16777216], ['scaled', 1], ['negative-zero', -0], ['tiny', 1.401298464324817e-45], ['infinity', Infinity]] as const) add(name, 'Float', [], exact(floating(expected)));
      add('identity', 'Float', [argDouble(16777217, true)], exact(floating(16777216)));
      for (const [name, expected] of [['wider', 9007199254740994], ['double-zero', -0], ['double-tiny', Number.MIN_VALUE], ['double-infinity', Infinity]] as const) add(name, 'Double', [], exact(floating(expected)));
      add('invalid', 'Float', [], { kind: 'category', category: 'nan' });
      add('double-invalid', 'Double', [], { kind: 'category', category: 'nan' });
      break;
    case 'math':
      for (const reference of model.mathReferences) {
        const value = ['root-zero', 'sine-zero', 'absolute-zero'].includes(reference.name) ? -0 : reference.expected;
        add(reference.name, 'Double', [], reference.ulps === 0 ? exact(floating(value)) : { kind: 'ulp', bits: bits(value), maxUlps: reference.ulps });
      }
      for (const reference of model.mathCategories) add(reference.name, 'Double', [], { kind: 'category', category: reference.category });
      add('mixed', 'Double', [argText('abcd'), argBool(false), argInt32('1'), argDouble(-3)], exact(floating(3)));
      add('mixed', 'Double', [argText('a'), argBool(true), argInt32('1'), argDouble(-3)], exact(floating(3)));
      break;
    case 'conversions': {
      const inputs = [-2.5, -1.5, -0.5, -0, 0.5, 1.5, 2.5];
      const expected = {
        rounded: ['-2', '-1', '0', '0', '1', '2', '3'],
        floored: ['-3', '-2', '-1', '0', '0', '1', '2'],
        ceiling: ['-2', '-1', '0', '0', '1', '2', '3'],
        truncated: ['-2', '-1', '0', '0', '0', '1', '2'],
      };
      for (const [name, values] of Object.entries(expected)) {
        for (const [i, value] of inputs.entries()) add(name, 'Integer', [argDouble(value)], exact(integer(values[i]!)));
        add(name, 'Integer', [argDouble(9007199254740992)], exact(integer('9007199254740992')));
        add(name, 'Integer', [argDouble(1e100)], exact(integer('10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104')));
        for (const value of [Infinity, -Infinity, NaN]) add(name, 'Integer', [argDouble(value)], exact({ type: 'model-error', code: 'sdk.invalid_number' }));
      }
      for (const [name, positive, negative] of [['exact', null, null], ['trunc', '1', '-1'], ['floor', '1', '-2'], ['ceil', '2', '-1'], ['round', '2', '-1']] as const) {
        for (const [value, wanted] of [[1.5, positive], [-1.5, negative], [2, '2'], [-0, '0'], [Infinity, null], [NaN, null]] as const) add(name, 'Integer?', [argDouble(value)], exact(wanted === null ? nothing() : just(integer(wanted))));
      }
      const edge = argInteger('9007199254740993');
      const exactly = argInteger('9007199254740992');
      add('floating', 'Double', [edge], exact(floating(9007199254740992)));
      add('to-rounded', 'Double', [edge], exact(floating(9007199254740992)));
      add('to-exact', 'Double?', [edge], exact(nothing()));
      add('to-exact', 'Double?', [exactly], exact(just(floating(9007199254740992))));
      const huge = argInteger('1' + '0'.repeat(400));
      add('to-exact', 'Double?', [huge], exact(nothing()));
      add('to-rounded', 'Double', [huge], exact(floating(Infinity)));
      add('absolute', 'Integer', [argInteger('-9007199254740993')], exact(integer('9007199254740993')));
      add('before', 'Bool', [exactly, edge], exact(bool(true)));
      add('before', 'Bool', [edge, exactly], exact(bool(false)));
      for (const flag of [false, true]) {
        add('optional', 'Integer?', [argMaybeInteger('9007199254740993'), argBool(flag)], exact(just(integer('9007199254740993'))));
        add('optional', 'Integer?', [argMaybeInteger(null), argBool(flag)], exact(nothing()));
      }
      break;
    }
    case 'decimal':
      for (const reference of model.decimalReferences) add(reference.name, 'Decimal', reference.args.map(argText), decimalReference(reference.expected));
      for (const reference of model.decimalComparisons) add(reference.name, 'Bool', [argText(reference.a), argText(reference.b)], exact(bool(reference.expected)));
      for (const reference of model.decimalFailures) add(reference.name, 'Decimal', reference.args.map(argText), exact({ type: 'model-error', code: 'sdk.decimal.' + reference.code }));
      add('identity', 'Decimal', [argDecimal('12.3400')], decimalReference('12.34'));
      break;
    default: throw new Error('Not a numeric fixture: ' + model.id);
  }
  return rows;
}

export function fullCorpus(fixtures: { models: TypedNumericModel[] }): NumericModel[] {
  return numericModelIds.map(id => {
    const model = fixtures.models.find(model => model.id === id);
    assert.ok(model, 'Missing numeric source fixture ' + id);
    assert.equal(model.profile, numericSourceProfile, 'N6 validates experimental capabilities without promoting them');
    assert.ok(model.sourceEntries.length, 'Fixture must distinguish source entries from IR-only SDK entries');
    const rows = rowsFor(model);
    const names = model.sourceEntries.map(entry => entry.split('#')[1]!);
    assert.deepEqual(new Set(rows.map(row => row.name)), new Set(names), 'Every offered numeric source entry needs independent rows: ' + id);
    assert.ok(rows.every(row => !model.irOnlyEntries.some(entry => entry.endsWith('#' + row.name))), 'IR-only SDK conversion support is not source admission');
    return { profile: numericSourceProfile, id, source: model.source, entries: names, rows };
  });
}
