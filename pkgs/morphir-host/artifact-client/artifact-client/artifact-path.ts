import { unicode17Nfc, unicode17Nfkc, unicode9FullDefaultCaseFold } from './artifact-unicode.ts'

declare const relativeArtifactPath: unique symbol
declare const portableArtifactKeyBrand: unique symbol
declare const artifactPathSetBrand: unique symbol

export type RelativeArtifactPath = string & { readonly [relativeArtifactPath]: true }
export type PortableArtifactKey = string & { readonly [portableArtifactKeyBrand]: true }
export type ArtifactPathSet = readonly RelativeArtifactPath[] & {
  readonly [artifactPathSetBrand]: true
}
export type ArtifactPathError =
  | 'artifact.invalid_path'
  | 'artifact.path_collision'
  | 'artifact.path_prefix'
  | 'artifact.path_limit'
export type ArtifactPathResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: ArtifactPathError }

const encoder = new TextEncoder()
const asciiUpper = (text: string): string =>
  text.replace(/[a-z]/g, (character) => String.fromCharCode(character.charCodeAt(0) - 32))

/** Rust RelativeArtifactPath rules plus this transfer draft's DEL/C1 supplement. No filesystem access. */
export function parseRelativeArtifactPath(
  input: unknown,
): ArtifactPathResult<RelativeArtifactPath> {
  const invalid = { ok: false, error: 'artifact.invalid_path' } as const
  if (typeof input !== 'string' || input.length === 0 || input.length > 1024) return invalid
  if (encoder.encode(input).length > 4096 || /[\\:]/.test(input)) return invalid
  for (const character of input) {
    const scalar = character.codePointAt(0)!
    if (scalar < 32 || (scalar >= 127 && scalar <= 159) || (scalar >= 0xd800 && scalar <= 0xdfff))
      return invalid
  }
  for (const component of input.split('/')) {
    const stem = asciiUpper(component.split('.')[0]!.replace(/ +$/, ''))
    if (
      component.length === 0 ||
      component.length > 255 ||
      encoder.encode(component).length > 255 ||
      component === '.' ||
      component === '..' ||
      /[. ]$/.test(component) ||
      /[<>:"|?*]/.test(component) ||
      /^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9¹²³]|LPT[1-9¹²³])$/.test(stem)
    )
      return invalid
  }
  return { ok: true, value: input as RelativeArtifactPath }
}

/** Collision identity only. The original path remains the display/archive spelling. */
export function portableArtifactKey(path: RelativeArtifactPath): PortableArtifactKey {
  return pathKey(path) as PortableArtifactKey
}

function pathKey(text: string): string {
  return unicode17Nfc(unicode9FullDefaultCaseFold(unicode17Nfkc(text)))
}

/** Validates the whole inventory before any file becomes downloadable. */
export function validateArtifactPathSet(
  paths: readonly RelativeArtifactPath[],
): ArtifactPathResult<ArtifactPathSet> {
  if (paths.length > 256) return { ok: false, error: 'artifact.path_limit' }
  const keys = new Set<PortableArtifactKey>()
  const parentSpellings = new Map<string, string>()
  for (const path of paths) {
    const key = portableArtifactKey(path)
    if (keys.has(key)) return { ok: false, error: 'artifact.path_collision' }
    keys.add(key)
    const components = path.split('/')
    const parentComponents: string[] = []
    const parentKeys: string[] = []
    for (const component of components.slice(0, -1)) {
      parentComponents.push(component)
      parentKeys.push(pathKey(component))
      // JSON preserves component boundaries even when NFKC introduces a slash.
      const identity = JSON.stringify(parentKeys)
      const spelling = parentComponents.join('/')
      const previous = parentSpellings.get(identity)
      if (previous !== undefined && previous !== spelling)
        return { ok: false, error: 'artifact.path_collision' }
      parentSpellings.set(identity, spelling)
    }
  }
  for (const key of keys) {
    for (
      let separator = key.indexOf('/');
      separator !== -1;
      separator = key.indexOf('/', separator + 1)
    ) {
      if (keys.has(key.slice(0, separator) as PortableArtifactKey))
        return { ok: false, error: 'artifact.path_prefix' }
    }
  }
  return { ok: true, value: Object.freeze([...paths]) as ArtifactPathSet }
}
