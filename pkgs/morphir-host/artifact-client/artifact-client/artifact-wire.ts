/** Private literal-preserving JSON boundary for the exact artifact draft. */
export const ARTIFACT_MAX_REPLY_BYTES = 128 * 1024
export const ARTIFACT_ERROR_CODES = [
  'artifacts.invalid_request',
  'artifacts.invalid_identity',
  'artifacts.invalid_range',
  'artifacts.invalid_path',
  'artifacts.invalid_path_set',
  'artifacts.invalid_content',
  'artifacts.file_count',
  'artifacts.file_size',
  'artifacts.set_size',
  'artifacts.reply_limit',
  'artifacts.capacity',
  'artifacts.active_generation',
  'artifacts.unknown_handle',
  'artifacts.unavailable',
  'artifacts.generation_failed',
] as const
export type ArtifactErrorCode = (typeof ARTIFACT_ERROR_CODES)[number]
export type ArtifactClientFailure =
  | { readonly kind: 'invalid'; readonly code: ArtifactErrorCode }
  | {
      readonly kind: 'remote'
      readonly code: ArtifactErrorCode
      readonly rpcCode: number
      readonly message: string
    }
export type ArtifactResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: ArtifactClientFailure }

export class ArtifactBoundaryFailure extends Error {
  readonly code: ArtifactErrorCode
  constructor(code: ArtifactErrorCode) {
    super(code)
    this.code = code
  }
}
export class ArtifactRemoteFailure extends Error {
  readonly failure: Extract<ArtifactClientFailure, { kind: 'remote' }>
  constructor(failure: Extract<ArtifactClientFailure, { kind: 'remote' }>) {
    super(failure.code)
    this.failure = failure
  }
}
export function refuse(code: ArtifactErrorCode = 'artifacts.invalid_request'): never {
  throw new ArtifactBoundaryFailure(code)
}
export function boundary<T>(read: () => T): ArtifactResult<T> {
  try {
    return { ok: true, value: read() }
  } catch (error) {
    if (error instanceof ArtifactRemoteFailure) return { ok: false, error: error.failure }
    return {
      ok: false,
      error: {
        kind: 'invalid',
        code: error instanceof ArtifactBoundaryFailure ? error.code : 'artifacts.invalid_request',
      },
    }
  }
}
export function wellFormed(text: string): boolean {
  for (const character of text) {
    const point = character.codePointAt(0)!
    if (point >= 0xd800 && point <= 0xdfff) return false
  }
  return true
}
export const utf8Length = (text: string): number => new TextEncoder().encode(text).length

// A source object cannot forge this token through a special JSON member name.
export class ExactJsonNumber {
  readonly lexeme: string
  constructor(lexeme: string) {
    this.lexeme = lexeme
  }
}
export type ExactJson =
  null | boolean | string | ExactJsonNumber | ReadonlyMap<string, ExactJson> | readonly ExactJson[]

class ExactJsonReader {
  private position = 0
  private remainingNodes = 100000
  private readonly text: string
  constructor(text: string) {
    this.text = text
  }
  read(): ExactJson {
    const value = this.value(0)
    this.whitespace()
    if (this.position !== this.text.length) refuse()
    return value
  }
  private whitespace(): void {
    while (' \t\r\n'.includes(this.text[this.position] ?? '\0')) this.position++
  }
  private string(): string {
    const start = this.position++
    while (this.position < this.text.length) {
      const character = this.text[this.position++]!
      if (character === '\\') this.position++
      else if (character === '"') {
        const value: unknown = JSON.parse(this.text.slice(start, this.position))
        if (typeof value !== 'string' || !wellFormed(value)) refuse()
        return value
      }
    }
    return refuse()
  }
  private value(depth: number): ExactJson {
    if (depth > 128 || --this.remainingNodes < 0) refuse()
    this.whitespace()
    const first = this.text[this.position]
    if (first === '"') return this.string()
    if (first === '{') {
      this.position++
      const object = new Map<string, ExactJson>()
      this.whitespace()
      if (this.text[this.position] === '}') {
        this.position++
        return object
      }
      while (true) {
        this.whitespace()
        if (this.text[this.position] !== '"') refuse()
        const key = this.string()
        if (object.has(key)) refuse()
        this.whitespace()
        if (this.text[this.position++] !== ':') refuse()
        object.set(key, this.value(depth + 1))
        this.whitespace()
        const separator = this.text[this.position++]
        if (separator === '}') return object
        if (separator !== ',') refuse()
      }
    }
    if (first === '[') {
      this.position++
      const values: ExactJson[] = []
      this.whitespace()
      if (this.text[this.position] === ']') {
        this.position++
        return values
      }
      while (true) {
        values.push(this.value(depth + 1))
        this.whitespace()
        const separator = this.text[this.position++]
        if (separator === ']') return values
        if (separator !== ',') refuse()
      }
    }
    for (const [token, value] of [
      ['null', null],
      ['true', true],
      ['false', false],
    ] as const) {
      if (this.text.startsWith(token, this.position)) {
        this.position += token.length
        return value
      }
    }
    const number = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y
    number.lastIndex = this.position
    const match = number.exec(this.text)
    if (!match) return refuse()
    this.position = number.lastIndex
    return new ExactJsonNumber(match[0])
  }
}

export function parseArtifactFrame(raw: string): ExactJson {
  if (typeof raw !== 'string') refuse()
  if (raw.length > ARTIFACT_MAX_REPLY_BYTES || utf8Length(raw) > ARTIFACT_MAX_REPLY_BYTES)
    refuse('artifacts.reply_limit')
  if (!wellFormed(raw)) refuse()
  return new ExactJsonReader(raw).read()
}

export function closed(
  value: ExactJson,
  fields: readonly string[],
): ReadonlyMap<string, ExactJson> {
  if (
    !(value instanceof Map) ||
    value.size !== fields.length ||
    fields.some((field) => !value.has(field))
  )
    return refuse()
  return value
}
export function text(value: ExactJson): string {
  if (typeof value !== 'string') return refuse()
  return value
}
export function array(value: ExactJson): readonly ExactJson[] {
  if (!Array.isArray(value)) return refuse()
  return value
}

/** Exact decimal integrality, before any binary floating-point conversion. */
export function integer(
  value: ExactJson,
  minimum: number,
  maximum: number,
  code: ArtifactErrorCode = 'artifacts.invalid_range',
): number {
  if (!(value instanceof ExactJsonNumber)) return refuse(code)
  const match = /^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/.exec(value.lexeme)!
  const fractional = match[3] ?? ''
  const significant = (match[2]! + fractional).replace(/^0+/, '')
  // All spellings of zero, including negative zero and huge exponents, denote zero.
  if (significant.length === 0) {
    if (minimum > 0 || maximum < 0) return refuse(code)
    return 0
  }
  const exponentText = (match[4] ?? '0').replace(/^([+-]?)0+/, '$1')
  if (exponentText.replace(/^[+-]/, '').length > 6) return refuse(code)
  const exponent = Number(
    exponentText === '' || exponentText === '+' || exponentText === '-' ? '0' : exponentText,
  )
  const power = exponent - fractional.length
  const digitCount = significant.length + power
  const maxDigits = Math.max(Math.abs(minimum), Math.abs(maximum)).toString().length
  if (digitCount < 1 || digitCount > maxDigits) return refuse(code)
  let integral: string
  if (power < 0) {
    if (!/^0*$/.test(significant.slice(digitCount))) return refuse(code)
    integral = significant.slice(0, digitCount)
  } else integral = significant + '0'.repeat(power)
  const number = Number(integral) * (match[1] === '-' ? -1 : 1)
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) return refuse(code)
  return number
}
