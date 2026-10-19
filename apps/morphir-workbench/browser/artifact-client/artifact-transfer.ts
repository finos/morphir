import { format, parse } from '@std/semver'
import {
  parseRelativeArtifactPath,
  validateArtifactPathSet,
  type RelativeArtifactPath,
} from './artifact-path.ts'
import {
  array,
  ARTIFACT_ERROR_CODES,
  ARTIFACT_MAX_REPLY_BYTES,
  ArtifactRemoteFailure,
  boundary,
  closed,
  ExactJsonNumber,
  integer,
  parseArtifactFrame,
  refuse,
  text,
  utf8Length,
  wellFormed,
  type ArtifactErrorCode,
  type ArtifactResult,
  type ExactJson,
} from './artifact-wire.ts'

export type { ArtifactResult, ArtifactClientFailure, ArtifactErrorCode } from './artifact-wire.ts'
export const ARTIFACT_PROFILE = 'morphir/workbench/artifacts' as const
export const ARTIFACT_CONTRACT_VERSION = '0.1.0-draft.1' as const
export const ARTIFACT_METHODS = Object.freeze({
  generate: 'morphir.artifacts.generate',
  read: 'morphir.artifacts.read',
  release: 'morphir.artifacts.release',
})
export const ARTIFACT_LIMITS = Object.freeze({
  files: 256,
  fileBytes: 16777216,
  aggregateBytes: 67108864,
  replyBytes: ARTIFACT_MAX_REPLY_BYTES,
  chunkBytes: 65536,
  chunkBase64Characters: 87384,
  generateRequestBytes: 1048576,
  readReleaseRequestBytes: 16384,
})

declare const identityBrand: unique symbol
type Identity<Kind extends string> = string & { readonly [identityBrand]: Kind }
export type ArtifactGenerationId = Identity<'generation'>
export type ArtifactId = Identity<'artifact'>
export type ArtifactSessionId = Identity<'session'>
export type ArtifactProviderId = Identity<'provider'>
export type ArtifactProducerId = Identity<'producer'>
export type ArtifactTarget = Identity<'target'>
export type ArtifactIrVersion = Identity<'ir-version'>
export type ArtifactProducerVersion = Identity<'producer-version'>
export type ArtifactSha256 = Identity<'sha256'>
export type ArtifactRequestId = Identity<'request-id'>
declare const byteLengthBrand: unique symbol
export type ArtifactByteLength = number & { readonly [byteLengthBrand]: true }
declare const validatedDomainBrand: unique symbol
type ValidatedDomain<Kind extends string> = { readonly [validatedDomainBrand]: Kind }
function validated<T extends ValidatedDomain<string>>(
  value: Omit<T, typeof validatedDomainBrand>,
): T {
  return Object.freeze(value) as T
}
declare const offsetBrand: unique symbol
declare const limitBrand: unique symbol
declare const base64Brand: unique symbol
export type ArtifactByteOffset = number & { readonly [offsetBrand]: true }
export type ArtifactChunkLimit = number & { readonly [limitBrand]: true }
export type CanonicalArtifactBase64 = string & { readonly [base64Brand]: true }

/** Structural projection of the existing WorkbenchProvider, independent of its Effect schema. */
export interface ArtifactProviderOffer {
  readonly id: string
  readonly status: 'available' | 'disconnected'
  readonly capabilities: readonly { readonly name: string; readonly version: string }[]
}
export interface ArtifactDiagnosticPosition {
  readonly line: number
  readonly character: number
}
export interface ArtifactDiagnosticLocation {
  readonly uri: string
  readonly range: {
    readonly start: ArtifactDiagnosticPosition
    readonly end: ArtifactDiagnosticPosition
  }
}
/** Exact-profile diagnostics preserve the existing shape and require every nullable field. */
export interface ArtifactDiagnostic {
  readonly severity: 'error' | 'warning' | 'info' | 'hint'
  readonly code: string | null
  readonly message: string
  readonly location: ArtifactDiagnosticLocation | null
}

export interface ArtifactProfileSelection extends ValidatedDomain<'profile-selection'> {
  readonly profile: typeof ARTIFACT_PROFILE
  readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
  readonly providerId: ArtifactProviderId
}
export interface ArtifactGenerationCapture extends ValidatedDomain<'generation-capture'> {
  readonly selection: ArtifactProfileSelection
  readonly sessionId: ArtifactSessionId
  readonly target: ArtifactTarget
  readonly irVersion: ArtifactIrVersion
}
export interface GeneratedArtifactDescriptor extends ValidatedDomain<'artifact-descriptor'> {
  readonly id: ArtifactId
  readonly path: RelativeArtifactPath
  readonly kind: 'utf8-text' | 'binary'
  readonly byteLength: ArtifactByteLength
  readonly sha256: ArtifactSha256
}
export interface GeneratedArtifactManifest extends ValidatedDomain<'artifact-manifest'> {
  readonly status: 'ready'
  readonly profile: typeof ARTIFACT_PROFILE
  readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
  readonly sessionId: ArtifactSessionId
  readonly providerId: ArtifactProviderId
  readonly generationId: ArtifactGenerationId
  readonly producer: { readonly id: ArtifactProducerId; readonly version: ArtifactProducerVersion }
  readonly target: ArtifactTarget
  readonly irVersion: ArtifactIrVersion
  readonly artifacts: readonly GeneratedArtifactDescriptor[]
  readonly diagnostics: readonly ArtifactDiagnostic[]
}
export interface ArtifactGenerationFailed extends ValidatedDomain<'generation-failed'> {
  readonly status: 'failed'
  readonly profile: typeof ARTIFACT_PROFILE
  readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
  readonly diagnostics: readonly ArtifactDiagnostic[]
}
export type ArtifactGenerateResult = GeneratedArtifactManifest | ArtifactGenerationFailed

export interface ArtifactReadCapture extends ValidatedDomain<'read-capture'> {
  readonly parameters: {
    readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
    readonly generationId: ArtifactGenerationId
    readonly artifactId: ArtifactId
    readonly offset: ArtifactByteOffset
    readonly maxBytes: ArtifactChunkLimit
  }
  readonly artifact: GeneratedArtifactDescriptor
}
export interface ArtifactChunk extends ValidatedDomain<'artifact-chunk'> {
  readonly profile: typeof ARTIFACT_PROFILE
  readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
  readonly generationId: ArtifactGenerationId
  readonly artifactId: ArtifactId
  readonly offset: ArtifactByteOffset
  readonly nextOffset: ArtifactByteOffset
  readonly content: CanonicalArtifactBase64
}
export interface ArtifactReleaseCapture extends ValidatedDomain<'release-capture'> {
  readonly parameters: {
    readonly contractVersion: typeof ARTIFACT_CONTRACT_VERSION
    readonly generationId: ArtifactGenerationId
  }
}
export interface ArtifactReleaseAcknowledgement {
  readonly generationId: ArtifactGenerationId
}

function identity<Kind extends string>(value: unknown): Identity<Kind> {
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length > 128 ||
    !wellFormed(value) ||
    utf8Length(value) > 128
  )
    return refuse('artifacts.invalid_identity')
  for (const character of value) {
    const point = character.codePointAt(0)!
    if (point < 32 || (point >= 127 && point <= 159)) return refuse('artifacts.invalid_identity')
  }
  return value as Identity<Kind>
}
function canonicalVersion(value: unknown): string {
  if (
    typeof value !== 'string' ||
    !wellFormed(value) ||
    utf8Length(value) > ARTIFACT_LIMITS.replyBytes
  )
    return refuse()
  try {
    if (format(parse(value)) === value) return value
  } catch {
    /* invalid SemVer */
  }
  return refuse()
}

/** Select only this exact draft; this does not modify connected v1 selection. */
export function selectArtifactTransferProfile(
  provider: ArtifactProviderOffer,
): ArtifactResult<ArtifactProfileSelection> {
  return boundary(() => {
    const providerId = identity<'provider'>(provider.id)
    if (provider.status !== 'available') refuse('artifacts.unavailable')
    const offers = provider.capabilities.filter((offer) => offer.name === ARTIFACT_PROFILE)
    if (
      !offers.some((offer) => {
        try {
          return canonicalVersion(offer.version) === ARTIFACT_CONTRACT_VERSION
        } catch {
          return false
        }
      })
    )
      refuse('artifacts.unavailable')
    return validated<ArtifactProfileSelection>({
      profile: ARTIFACT_PROFILE,
      contractVersion: ARTIFACT_CONTRACT_VERSION,
      providerId,
    })
  })
}
/** Call synchronously before awaiting generation; retain the caller's source/request capture alongside it. */
export function captureArtifactGeneration(
  selection: ArtifactProfileSelection,
  input: { readonly sessionId: string; readonly target: string; readonly irVersion: string },
): ArtifactResult<ArtifactGenerationCapture> {
  return boundary(() => {
    if (
      selection.profile !== ARTIFACT_PROFILE ||
      selection.contractVersion !== ARTIFACT_CONTRACT_VERSION
    )
      refuse('artifacts.unavailable')
    return validated<ArtifactGenerationCapture>({
      selection: Object.freeze({
        ...selection,
        providerId: identity<'provider'>(selection.providerId),
      }),
      sessionId: identity<'session'>(input.sessionId),
      target: identity<'target'>(input.target),
      irVersion: identity<'ir-version'>(input.irVersion),
    })
  })
}

/** Decimal u64 identity avoids precision loss and preserves connected request-ID syntax. */
export function parseArtifactRequestId(input: unknown): ArtifactResult<ArtifactRequestId> {
  return boundary(() => {
    const decimal =
      typeof input === 'bigint'
        ? input.toString()
        : typeof input === 'number' && Number.isSafeInteger(input) && input >= 0
          ? input.toString()
          : input
    if (
      typeof decimal !== 'string' ||
      !/^(0|[1-9][0-9]{0,19})$/.test(decimal) ||
      BigInt(decimal) > 18446744073709551615n
    )
      return refuse()
    return decimal as ArtifactRequestId
  })
}

function profile(object: ReadonlyMap<string, ExactJson>): void {
  if (
    object.get('profile') !== ARTIFACT_PROFILE ||
    object.get('contractVersion') !== ARTIFACT_CONTRACT_VERSION
  )
    refuse('artifacts.unavailable')
}
function position(value: ExactJson): ArtifactDiagnosticPosition {
  const point = closed(value, ['line', 'character'])
  return Object.freeze({
    line: integer(point.get('line')!, 0, 4294967295),
    character: integer(point.get('character')!, 0, 4294967295),
  })
}
function diagnostics(value: ExactJson): readonly ArtifactDiagnostic[] {
  return Object.freeze(
    array(value).map((raw) => {
      const diagnostic = closed(raw, ['severity', 'code', 'message', 'location'])
      const severity = text(diagnostic.get('severity')!)
      if (
        severity !== 'error' &&
        severity !== 'warning' &&
        severity !== 'info' &&
        severity !== 'hint'
      )
        refuse()
      const code = diagnostic.get('code') === null ? null : text(diagnostic.get('code')!)
      let location: ArtifactDiagnosticLocation | null = null
      if (diagnostic.get('location') !== null) {
        const source = closed(diagnostic.get('location')!, ['uri', 'range'])
        const range = closed(source.get('range')!, ['start', 'end'])
        location = Object.freeze({
          uri: text(source.get('uri')!),
          range: Object.freeze({
            start: position(range.get('start')!),
            end: position(range.get('end')!),
          }),
        })
      }
      return Object.freeze({ severity, code, message: text(diagnostic.get('message')!), location })
    }),
  )
}
function descriptor(value: ExactJson): GeneratedArtifactDescriptor {
  const object = closed(value, ['id', 'path', 'kind', 'byteLength', 'sha256'])
  const path = parseRelativeArtifactPath(text(object.get('path')!))
  if (!path.ok) return refuse('artifacts.invalid_path')
  const kind = text(object.get('kind')!)
  if (kind !== 'utf8-text' && kind !== 'binary') return refuse()
  const digest = text(object.get('sha256')!)
  if (!/^[0-9a-f]{64}$/.test(digest)) return refuse('artifacts.invalid_content')
  return validated<GeneratedArtifactDescriptor>({
    id: identity<'artifact'>(object.get('id')),
    path: path.value,
    kind,
    byteLength: integer(
      object.get('byteLength')!,
      0,
      ARTIFACT_LIMITS.fileBytes,
      'artifacts.file_size',
    ) as ArtifactByteLength,
    sha256: digest as ArtifactSha256,
  })
}
function generateResult(
  value: ExactJson,
  capture: ArtifactGenerationCapture,
): ArtifactGenerateResult {
  if (!(value instanceof Map)) return refuse()
  if (value.get('status') === 'failed') {
    const object = closed(value, ['status', 'profile', 'contractVersion', 'diagnostics'])
    profile(object)
    return validated<ArtifactGenerationFailed>({
      status: 'failed',
      profile: ARTIFACT_PROFILE,
      contractVersion: ARTIFACT_CONTRACT_VERSION,
      diagnostics: diagnostics(object.get('diagnostics')!),
    })
  }
  const object = closed(value, [
    'status',
    'profile',
    'contractVersion',
    'sessionId',
    'providerId',
    'generationId',
    'producer',
    'target',
    'irVersion',
    'artifacts',
    'diagnostics',
  ])
  profile(object)
  if (object.get('status') !== 'ready') return refuse()
  const sessionId = identity<'session'>(object.get('sessionId'))
  const providerId = identity<'provider'>(object.get('providerId'))
  const target = identity<'target'>(object.get('target'))
  const irVersion = identity<'ir-version'>(object.get('irVersion'))
  if (
    sessionId !== capture.sessionId ||
    providerId !== capture.selection.providerId ||
    target !== capture.target ||
    irVersion !== capture.irVersion
  )
    refuse('artifacts.invalid_identity')
  const producer = closed(object.get('producer')!, ['id', 'version'])
  const inventory = array(object.get('artifacts')!)
  if (inventory.length > ARTIFACT_LIMITS.files) return refuse('artifacts.file_count')
  const artifacts = Object.freeze(inventory.map(descriptor))
  const paths = validateArtifactPathSet(artifacts.map((artifact) => artifact.path))
  if (!paths.ok) return refuse('artifacts.invalid_path_set')
  if (new Set(artifacts.map((artifact) => artifact.id)).size !== artifacts.length)
    refuse('artifacts.invalid_identity')
  if (
    artifacts.reduce((total, artifact) => total + artifact.byteLength, 0) >
    ARTIFACT_LIMITS.aggregateBytes
  )
    refuse('artifacts.set_size')
  return validated<GeneratedArtifactManifest>({
    status: 'ready',
    profile: ARTIFACT_PROFILE,
    contractVersion: ARTIFACT_CONTRACT_VERSION,
    sessionId,
    providerId,
    generationId: identity<'generation'>(object.get('generationId')),
    producer: Object.freeze({
      id: identity<'producer'>(producer.get('id')),
      version: canonicalVersion(producer.get('version')) as ArtifactProducerVersion,
    }),
    target,
    irVersion,
    artifacts,
    diagnostics: diagnostics(object.get('diagnostics')!),
  })
}

function reply<T>(
  raw: string,
  expectedId: ArtifactRequestId,
  decode: (value: ExactJson) => T,
): ArtifactResult<T> {
  return boundary(() => {
    const frame = parseArtifactFrame(raw)
    if (!(frame instanceof Map)) return refuse()
    const remote = frame.has('error')
    const object = closed(frame, ['jsonrpc', 'id', remote ? 'error' : 'result'])
    if (object.get('jsonrpc') !== '2.0') refuse()
    const id = object.get('id')
    if (
      !(id instanceof ExactJsonNumber) ||
      !/^(0|[1-9][0-9]{0,19})$/.test(id.lexeme) ||
      id.lexeme !== expectedId
    )
      refuse('artifacts.invalid_identity')
    if (remote) {
      const error = closed(object.get('error')!, ['code', 'message', 'data'])
      const data = closed(error.get('data')!, ['profile', 'contractVersion', 'code'])
      profile(data)
      const code = text(data.get('code')!)
      if (!(ARTIFACT_ERROR_CODES as readonly string[]).includes(code)) return refuse()
      throw new ArtifactRemoteFailure(
        Object.freeze({
          kind: 'remote',
          code: code as ArtifactErrorCode,
          rpcCode: integer(error.get('code')!, -2147483648, 2147483647),
          message: text(error.get('message')!),
        }),
      )
    }
    return decode(object.get('result')!)
  })
}

/** A valid manifest describes bytes; it does not prove that any file was received or saved. */
export function decodeArtifactGenerateReply(
  raw: string,
  capture: ArtifactGenerationCapture,
  requestId: ArtifactRequestId,
): ArtifactResult<ArtifactGenerateResult> {
  return reply(raw, requestId, (value) => generateResult(value, capture))
}

/** Captures the exact immutable file and requested interval before an RPC await. */
export function captureArtifactRead(
  manifest: GeneratedArtifactManifest,
  artifactId: ArtifactId,
  offset: number,
  maxBytes: number,
): ArtifactResult<ArtifactReadCapture> {
  return boundary(() => {
    const artifact = manifest.artifacts.find((entry) => entry.id === artifactId)
    if (!artifact) return refuse('artifacts.unknown_handle')
    if (
      !Number.isSafeInteger(offset) ||
      offset < 0 ||
      offset > artifact.byteLength ||
      !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1 ||
      maxBytes > ARTIFACT_LIMITS.chunkBytes
    )
      return refuse('artifacts.invalid_range')
    return validated<ArtifactReadCapture>({
      artifact,
      parameters: Object.freeze({
        contractVersion: ARTIFACT_CONTRACT_VERSION,
        generationId: manifest.generationId,
        artifactId,
        offset: (offset === 0 ? 0 : offset) as ArtifactByteOffset,
        maxBytes: maxBytes as ArtifactChunkLimit,
      }),
    })
  })
}

const BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function canonicalBase64(value: ExactJson): {
  readonly content: CanonicalArtifactBase64
  readonly byteLength: number
} {
  const encoded = text(value)
  if (
    encoded.length > ARTIFACT_LIMITS.chunkBase64Characters ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)
  )
    return refuse('artifacts.invalid_content')
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0
  if (padding === 2 && (BASE64_ALPHABET.indexOf(encoded.at(-3)!) & 15) !== 0)
    return refuse('artifacts.invalid_content')
  if (padding === 1 && (BASE64_ALPHABET.indexOf(encoded.at(-2)!) & 3) !== 0)
    return refuse('artifacts.invalid_content')
  const byteLength = (encoded.length / 4) * 3 - padding
  if (byteLength > ARTIFACT_LIMITS.chunkBytes) return refuse('artifacts.invalid_content')
  return { content: encoded as CanonicalArtifactBase64, byteLength }
}

export function decodeArtifactReadReply(
  raw: string,
  capture: ArtifactReadCapture,
  requestId: ArtifactRequestId,
): ArtifactResult<ArtifactChunk> {
  return reply(raw, requestId, (value) => {
    const object = closed(value, [
      'profile',
      'contractVersion',
      'generationId',
      'artifactId',
      'offset',
      'nextOffset',
      'content',
    ])
    profile(object)
    const generationId = identity<'generation'>(object.get('generationId'))
    const artifactId = identity<'artifact'>(object.get('artifactId'))
    if (
      generationId !== capture.parameters.generationId ||
      artifactId !== capture.parameters.artifactId
    )
      refuse('artifacts.invalid_identity')
    const offset = integer(object.get('offset')!, 0, ARTIFACT_LIMITS.fileBytes)
    const nextOffset = integer(object.get('nextOffset')!, 0, ARTIFACT_LIMITS.fileBytes)
    const decoded = canonicalBase64(object.get('content')!)
    const expectedLength = Math.min(
      capture.parameters.maxBytes,
      capture.artifact.byteLength - capture.parameters.offset,
    )
    if (
      offset !== capture.parameters.offset ||
      decoded.byteLength !== expectedLength ||
      nextOffset !== offset + decoded.byteLength
    )
      refuse('artifacts.invalid_range')
    return validated<ArtifactChunk>({
      profile: ARTIFACT_PROFILE,
      contractVersion: ARTIFACT_CONTRACT_VERSION,
      generationId,
      artifactId,
      offset: offset as ArtifactByteOffset,
      nextOffset: nextOffset as ArtifactByteOffset,
      content: decoded.content,
    })
  })
}

/** Returns a fresh byte buffer. The validated chunk itself retains immutable canonical text. */
export function artifactChunkBytes(chunk: ArtifactChunk): Uint8Array {
  const encoded = chunk.content
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0
  const bytes = new Uint8Array((encoded.length / 4) * 3 - padding)
  let position = 0
  for (let offset = 0; offset < encoded.length; offset += 4) {
    const bits =
      (BASE64_ALPHABET.indexOf(encoded[offset]!) << 18) |
      (BASE64_ALPHABET.indexOf(encoded[offset + 1]!) << 12) |
      (Math.max(0, BASE64_ALPHABET.indexOf(encoded[offset + 2]!)) << 6) |
      Math.max(0, BASE64_ALPHABET.indexOf(encoded[offset + 3]!))
    if (position < bytes.length) bytes[position++] = bits >>> 16
    if (position < bytes.length) bytes[position++] = bits >>> 8
    if (position < bytes.length) bytes[position++] = bits
  }
  return bytes
}

export function captureArtifactRelease(
  manifest: GeneratedArtifactManifest,
): ArtifactReleaseCapture {
  return validated<ArtifactReleaseCapture>({
    parameters: Object.freeze({
      contractVersion: ARTIFACT_CONTRACT_VERSION,
      generationId: manifest.generationId,
    }),
  })
}

/** An acknowledgement is not independent evidence that a host freed its reservations. */
export function decodeArtifactReleaseReply(
  raw: string,
  capture: ArtifactReleaseCapture,
  requestId: ArtifactRequestId,
): ArtifactResult<ArtifactReleaseAcknowledgement> {
  return reply(raw, requestId, (value) => {
    closed(value, [])
    return Object.freeze({ generationId: capture.parameters.generationId })
  })
}

function encodeRequest(
  method: typeof ARTIFACT_METHODS.read | typeof ARTIFACT_METHODS.release,
  parameters: ArtifactReadCapture['parameters'] | ArtifactReleaseCapture['parameters'],
  requestId: ArtifactRequestId,
): ArtifactResult<string> {
  return boundary(() => {
    const validatedId = parseArtifactRequestId(requestId)
    if (!validatedId.ok) return refuse('artifacts.invalid_identity')
    // The validated decimal ID stays a numeric token, even beyond JS's safe-integer range.
    const frame = `{"jsonrpc":"2.0","id":${validatedId.value},"method":${JSON.stringify(method)},"params":${JSON.stringify(parameters)}}`
    if (utf8Length(frame) > ARTIFACT_LIMITS.readReleaseRequestBytes)
      refuse('artifacts.invalid_request')
    return frame
  })
}
export function encodeArtifactReadRequest(
  capture: ArtifactReadCapture,
  requestId: ArtifactRequestId,
): ArtifactResult<string> {
  return encodeRequest(ARTIFACT_METHODS.read, capture.parameters, requestId)
}
export function encodeArtifactReleaseRequest(
  capture: ArtifactReleaseCapture,
  requestId: ArtifactRequestId,
): ArtifactResult<string> {
  return encodeRequest(ARTIFACT_METHODS.release, capture.parameters, requestId)
}
