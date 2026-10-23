import { recognize_projection_header } from './projection-header.js';

export type ProjectionHeaderFailureCode =
  | 'invalid-limits' | 'byte-limit' | 'invalid-utf8' | 'decode-limit' | 'invalid-header';

export class ProjectionHeaderFailure extends Error {
  constructor(readonly code: ProjectionHeaderFailureCode) {
    super(code);
    this.name = 'ProjectionHeaderFailure';
    Object.freeze(this);
  }
}

type LimitsSnapshot = Readonly<{ maxBytes: number; maxDepth: number; maxValues: number }>;
const ownedLimits = new WeakMap<ProjectionHeaderLimits, LimitsSnapshot>();
const int32Max = 2_147_483_647;

function snapshotLimits(input: unknown): LimitsSnapshot {
  try {
    if (typeof input !== 'object' || input === null) throw new ProjectionHeaderFailure('invalid-limits');
    const values = input as Record<string, unknown>;
    const maxBytes = values.maxBytes, maxDepth = values.maxDepth, maxValues = values.maxValues;
    const checked = (value: unknown, minimum: number): value is number =>
      typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum && value <= int32Max;
    if (!checked(maxBytes, 1) || !checked(maxDepth, 0) || !checked(maxValues, 1)) {
      throw new ProjectionHeaderFailure('invalid-limits');
    }
    return Object.freeze({ maxBytes, maxDepth, maxValues });
  } catch {
    throw new ProjectionHeaderFailure('invalid-limits');
  }
}

/** Explicit, owned Int32 parser bounds. There are no default acceptance limits. */
export class ProjectionHeaderLimits {
  declare private readonly projectionHeaderLimitsBrand: never;
  private constructor(input: unknown) {
    // Validate here as well as at the TypeScript surface: JavaScript callers
    // cannot bypass the invariant by invoking this constructor directly.
    ownedLimits.set(this, snapshotLimits(input));
    Object.freeze(this);
  }
  static create(input: unknown): ProjectionHeaderLimits { return new ProjectionHeaderLimits(input); }
}

const typedArrayPrototype: object = Object.getPrototypeOf(Uint8Array.prototype);
const typedArrayTag = Object.getOwnPropertyDescriptor(typedArrayPrototype, Symbol.toStringTag)!.get!;
const typedArrayBuffer = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer')!.get!;
const typedArrayLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength')!.get!;
const arrayBufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength')!.get!;

function snapshotBytes(input: Uint8Array, maximum: number): Uint8Array {
  try {
    if (!ArrayBuffer.isView(input) || typedArrayTag.call(input) !== 'Uint8Array') {
      throw new ProjectionHeaderFailure('invalid-header');
    }
    // The intrinsic getter rejects SharedArrayBuffer, including another realm's
    // instance, without consulting mutable constructor or Symbol.toStringTag data.
    arrayBufferLength.call(typedArrayBuffer.call(input));
    const length: number = typedArrayLength.call(input);
    if (length > maximum) throw new ProjectionHeaderFailure('byte-limit');
    const snapshot = new Uint8Array(length);
    // Avoid species constructors and input-owned accessors during the copy.
    Uint8Array.prototype.set.call(snapshot, input);
    return snapshot;
  } catch (error) {
    if (error instanceof ProjectionHeaderFailure) throw error;
    throw new ProjectionHeaderFailure('invalid-header');
  }
}

function refusal(code: unknown): ProjectionHeaderFailure {
  switch (code) {
    case 'data.invalid_limits': return new ProjectionHeaderFailure('invalid-limits');
    case 'data.byte_limit': return new ProjectionHeaderFailure('byte-limit');
    case 'data.invalid_utf8': return new ProjectionHeaderFailure('invalid-utf8');
    case 'json_limit': return new ProjectionHeaderFailure('decode-limit');
    default: return new ProjectionHeaderFailure('invalid-header');
  }
}

/** Recognize the actual whole projection header; this performs no typed
 * inspection, supported-version decision, transport request or model adoption. */
export function recognizeProjectionHeader(bytes: Uint8Array, limits: ProjectionHeaderLimits): string {
  const bounds = ownedLimits.get(limits);
  if (bounds === undefined) throw new ProjectionHeaderFailure('invalid-limits');
  const snapshot = snapshotBytes(bytes, bounds.maxBytes);
  try {
    const value: unknown = JSON.parse(recognize_projection_header(snapshot, bounds.maxBytes, bounds.maxDepth, bounds.maxValues));
    if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new ProjectionHeaderFailure('invalid-header');
    const result = value as Record<string, unknown>;
    const keys = Object.keys(result);
    if (keys.length !== 2) throw new ProjectionHeaderFailure('invalid-header');
    if (result.kind === 'recognized' && typeof result.release === 'string' && keys.includes('release')) return result.release;
    if (result.kind === 'refused' && keys.includes('code')) throw refusal(result.code);
    throw new ProjectionHeaderFailure('invalid-header');
  } catch (error) {
    if (error instanceof ProjectionHeaderFailure) throw error;
    throw new ProjectionHeaderFailure('invalid-header');
  }
}
