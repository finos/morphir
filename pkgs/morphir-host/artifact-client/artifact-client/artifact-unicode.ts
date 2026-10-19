import {
  combiningClass,
  composition,
  decomposition,
  fullDefaultCaseFold,
} from './artifact-unicode-data.ts'

// UAX #15, Unicode 17.0.0. Hangul mappings are algorithmic rather than UCD entries.
const HANGUL_BASE = 0xac00
const LEADING_BASE = 0x1100
const VOWEL_BASE = 0x1161
const TRAILING_BASE = 0x11a7
const VOWEL_COUNT = 21
const TRAILING_COUNT = 28
const HANGUL_BLOCK_SIZE = VOWEL_COUNT * TRAILING_COUNT
const HANGUL_COUNT = 19 * HANGUL_BLOCK_SIZE

function appendOrdered(output: number[], point: number): void {
  output.push(point)
  const currentClass = combiningClass[point] ?? 0
  if (currentClass === 0) return
  let position = output.length - 1
  while (position > 0 && (combiningClass[output[position - 1]!] ?? 0) > currentClass) {
    output[position] = output[position - 1]!
    position--
  }
  output[position] = point
}

function appendDecomposed(output: number[], point: number, compatibility: boolean): void {
  const hangul = point - HANGUL_BASE
  if (hangul >= 0 && hangul < HANGUL_COUNT) {
    appendOrdered(output, LEADING_BASE + Math.floor(hangul / HANGUL_BLOCK_SIZE))
    appendOrdered(output, VOWEL_BASE + Math.floor((hangul % HANGUL_BLOCK_SIZE) / TRAILING_COUNT))
    const trailing = hangul % TRAILING_COUNT
    if (trailing !== 0) appendOrdered(output, TRAILING_BASE + trailing)
    return
  }
  const entry = decomposition[point]
  if (entry && (compatibility || !entry.compatibility)) {
    for (const child of entry.mapping) appendDecomposed(output, child, compatibility)
  } else appendOrdered(output, point)
}

function compose(first: number, second: number): number | undefined {
  const leading = first - LEADING_BASE
  const vowel = second - VOWEL_BASE
  if (leading >= 0 && leading < 19 && vowel >= 0 && vowel < VOWEL_COUNT) {
    return HANGUL_BASE + (leading * VOWEL_COUNT + vowel) * TRAILING_COUNT
  }
  const syllable = first - HANGUL_BASE
  const trailing = second - TRAILING_BASE
  if (
    syllable >= 0 &&
    syllable < HANGUL_COUNT &&
    syllable % TRAILING_COUNT === 0 &&
    trailing > 0 &&
    trailing < TRAILING_COUNT
  ) {
    return first + trailing
  }
  return composition[first]?.[second]
}

function normalize(text: string, compatibility: boolean): string {
  const decomposed: number[] = []
  for (const character of text)
    appendDecomposed(decomposed, character.codePointAt(0)!, compatibility)
  if (decomposed.length === 0) return ''
  const output = [decomposed[0]!]
  let starterIndex = 0
  let starter = decomposed[0]!
  let previousClass = combiningClass[starter] ?? 0
  for (let index = 1; index < decomposed.length; index++) {
    const point = decomposed[index]!
    const currentClass = combiningClass[point] ?? 0
    const composed = compose(starter, point)
    if (composed !== undefined && (previousClass === 0 || previousClass < currentClass)) {
      output[starterIndex] = composed
      starter = composed
    } else {
      if (currentClass === 0) {
        starterIndex = output.length
        starter = point
      }
      output.push(point)
      previousClass = currentClass
    }
  }
  return output.map((point) => String.fromCodePoint(point)).join('')
}

export const unicode17Nfc = (text: string): string => normalize(text, false)
export const unicode17Nfkc = (text: string): string => normalize(text, true)

/** Full default folding selects C/F entries, excluding simple and Turkic mappings. */
export function unicode9FullDefaultCaseFold(text: string): string {
  let result = ''
  for (const character of text) {
    const mapping = fullDefaultCaseFold[character.codePointAt(0)!]
    result += mapping ? mapping.map((point) => String.fromCodePoint(point)).join('') : character
  }
  return result
}
