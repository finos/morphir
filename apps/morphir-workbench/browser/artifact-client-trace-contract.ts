/** Artifact-client MCK draft28 review-candidate measurement vocabulary.
 * Shared contract source: finos/morphir PR1069, independently reviewed client
 * proposal of 18 October 2026. Final shared schema/pin coordination is pending.
 * No expected outputs or case identities are inputs to this driver.
 * The shared runner validates closed input objects and pre-expansion budgets.
 * Initial context is null. Every attempt must start, settle and close before
 * final evidence; held states belong only to intermediate checkpoints.
 */
import type { ArtifactInputFailure } from './artifact-transfer.ts';
export type Json = null | boolean | number | string | readonly Json[] | { readonly [key: string]: Json };
declare const domain: unique symbol;
type Domain<T, Name extends string> = T & { readonly [domain]: Name };
export type AttemptId = Domain<string, 'attempt-id'>; // [A-Za-z][A-Za-z0-9_-]{0,63}
export type ViewId = Domain<string, 'view-id'>; // same alias grammar, scenario-unique
export type ObservationLabel = Domain<string, 'observation-label'>; // same grammar
export type FileAlias = Domain<string, 'file-alias'>; // file-0, file-1, ... in peer inventory order
export type EffectIndex = Domain<number, 'effect-index'>; // 0..4095, per-attempt invocation order
export type ActionIndex = Domain<number, 'action-index'>; // 0..511
export type Revision = Domain<number, 'source-revision'>; // exact integer 0..2147483647
export type Epoch = Domain<number, 'request-epoch'>; // exact integer 0..2147483647
export type SourceIdentity = Domain<string, 'source-identity'>; // existing source identity rule
export type ByteCount = Domain<number, 'byte-count'>;
export type ByteOffset = Domain<number, 'byte-offset'>;
export type ExactCount = Domain<number, 'exact-count'>;
export type Utf16Length = Domain<number, 'utf16-length'>; // 0..1048576
export type ReadCount = Domain<number, 'read-count'>; // 0..4096
export type U8 = Domain<number, 'u8'>;
export type U7 = Domain<number, 'ascii-byte'>;
export type Sha256 = Domain<string, 'sha256'>; // 64 lowercase hexadecimal characters
export type BoundedText = Domain<string, 'bounded-error-text'>; // well-formed, <=512 UTF16 units
export type ProtocolId = string | number; // actual integral wire ID; shared checker preserves literal evidence
export type LocalContext = Readonly<{ sourceId: SourceIdentity; revision: Revision; epoch: Epoch }>;
export type JsonPathStep = Readonly<{ kind: 'member'; key: string }> | Readonly<{ kind: 'index'; index: number }>;
export type JsonPath = readonly JsonPathStep[]; // <=32, existing steps only
export type Capability = Readonly<{ name: string; version: string }>;
export type ProviderOffer = Readonly<{ id: string; status: 'available' | 'disconnected'; capabilities: readonly Capability[] }>;
export type DiagnosticPosition = Readonly<{ line: number; character: number }>;
export type DiagnosticLocation = Readonly<{ uri: string; range: Readonly<{ start: DiagnosticPosition; end: DiagnosticPosition }> }>;
export type Diagnostic = Readonly<{ severity: 'error' | 'warning' | 'info' | 'hint'; code: string | null; message: string; location: DiagnosticLocation | null }>;
export type ByteRecipe = Readonly<{ kind: 'hex'; hex: string }>
  | Readonly<{ kind: 'cycle-u8'; length: ByteCount }>
  | Readonly<{ kind: 'chunk-indexed-u8'; length: ByteCount; seed: U8 }>
  | Readonly<{ kind: 'repeat-u8'; length: ByteCount; byte: U8 }>;
export type PeerFile = Readonly<{ id: string; path: string; kind: 'utf8-text' | 'binary'; content: ByteRecipe }>;
export type PeerRecipe = Readonly<{ kind: 'ready'; generationId: string; producer: Readonly<{ id: string; version: string }>; artifacts: readonly PeerFile[]; diagnostics: readonly Diagnostic[] }>
  | Readonly<{ kind: 'failed'; diagnostics: readonly Diagnostic[] }>;
export type LocalFault = Readonly<{ kind: 'unpaired-surrogate-value' | 'unpaired-surrogate-key'; field: 'ir' | 'options'; path: JsonPath; unit: 'high' | 'low' }>
  | Readonly<{ kind: 'nonfinite-number'; field: 'ir' | 'options'; path: JsonPath; value: 'nan' | 'positive-infinity' | 'negative-infinity' }>;
export type LocalValueRecipe = Readonly<{ kind: 'repeat-ascii-value'; field: 'ir' | 'options'; path: JsonPath; byte: U7; count: ByteCount }>;
export type AttemptDefinition = Readonly<{
  id: AttemptId; offer: ProviderOffer;
  input: Readonly<{ sessionId: string; target: string; irVersion: string; ir: Json; options: Json }>;
  context: LocalContext; peer: PeerRecipe; localFaults: readonly LocalFault[];
  localValues?: readonly LocalValueRecipe[];
}>;
export type FrameSegment = Readonly<{ kind: 'literal'; source: string }>
  | Readonly<{ kind: 'repeat-ascii'; byte: U7; count: ByteCount }>;
/** Text may occupy the complete bounded frame. Observed segment literals have
 * no separate16KiB ceiling; total expanded frame and evidence limits apply.
 * The16KiB ceiling applies only to authored input recipe literal segments.
 */
export type FrameSource = Readonly<{ kind: 'text'; source: string }>
  | Readonly<{ kind: 'segments'; segments: readonly FrameSegment[] }>;
export type EffectKind = 'connect' | 'initialize' | 'generate' | 'read' | 'digest' | 'release';
export type EffectRef = Readonly<{ attempt: AttemptId; index: EffectIndex; kind: EffectKind }>;
export type Delivery = Readonly<{ kind: 'connect' }> | Readonly<{ kind: 'peer' }>
  | Readonly<{ kind: 'raw'; frame: FrameSource }>
  | Readonly<{ kind: 'digest'; result: 'actual' | 'wrong-32' | 'short-31' }>
  | Readonly<{ kind: 'digest-mutated-input'; xor: U8 }>;
export type ViewMutation = Readonly<{ kind: 'path'; index: number; path: string }>
  | Readonly<{ kind: 'reference'; index: number; fromViews: ViewId; fromIndex: number }>;
/** Selects emitted view objects in order. Repeated indices deliberately test
 * duplicates. Mutations change private request copies, never the stored views.
 */
export type ViewSelection = Readonly<{ views: ViewId; indices: readonly number[]; mutations: readonly ViewMutation[] }>;
export type ClientAction = Readonly<{ action: 'start'; attempt: AttemptId }>
  | Readonly<{ action: 'deliver'; effect: EffectRef; value: Delivery }>
  | Readonly<{ action: 'reject'; effect: EffectRef; message: BoundedText }>
  | Readonly<{ action: 'drain-reads'; attempt: AttemptId; maxReads: ReadCount }>
  | Readonly<{ action: 'set-current'; context: LocalContext | null }>
  | Readonly<{ action: 'replace-caller'; attempt: AttemptId; field: 'ir' | 'options'; value: Json }>
  | Readonly<{ action: 'replace-effect-functions'; attempt: AttemptId }>
  | Readonly<{ action: 'cancel'; attempt: AttemptId }>
  | Readonly<{ action: 'close-channel'; attempt: AttemptId }>
  | Readonly<{ action: 'publish'; attempt: AttemptId; views: ViewId }>
  | Readonly<{ action: 'clear-registry' }>
  | Readonly<{ action: 'mutate-copy'; attempt: AttemptId; file: FileAlias; offset: ByteOffset; xor: U8 }>
  | Readonly<{ action: 'download'; views: ViewSelection; complete: boolean }>
  | Readonly<{ action: 'archive'; views: ViewSelection }>
  | Readonly<{ action: 'observe'; label: ObservationLabel }>;
export type ClientScenario = Readonly<{ attempts: readonly AttemptDefinition[]; actions: readonly ClientAction[] }>;
export type CapturedBinding = Readonly<{
  profile: 'morphir/workbench/artifacts'; contractVersion: '0.1.0-draft.1';
  providerId: string; sessionId: string; target: string; irVersion: string;
}>;
export type ManifestBinding = CapturedBinding & Readonly<{
  generationId: string; producer: Readonly<{ id: string; version: string }>;
  diagnostics: readonly Diagnostic[];
}>;
export type ArtifactCleanup = Readonly<{ kind: 'not-connected' }> | Readonly<{ kind: 'not-retained' }>
  | Readonly<{ kind: 'released'; generationId: string }>
  | Readonly<{ kind: 'connection-closed'; generationId: string | null; reason: 'pending-exchange' | 'unknown-retention' | 'release-failed' }>;
export type ArtifactErrorCode = 'artifacts.invalid_request' | 'artifacts.invalid_identity' | 'artifacts.invalid_range'
  | 'artifacts.invalid_path' | 'artifacts.invalid_path_set' | 'artifacts.invalid_content'
  | 'artifacts.file_count' | 'artifacts.file_size' | 'artifacts.set_size' | 'artifacts.reply_limit'
  | 'artifacts.capacity' | 'artifacts.active_generation' | 'artifacts.unknown_handle'
  | 'artifacts.unavailable' | 'artifacts.generation_failed';
export type ArtifactClientFailure = Readonly<{ kind: 'invalid'; code: ArtifactErrorCode }>
  | Readonly<{ kind: 'remote'; code: ArtifactErrorCode; rpcCode: number; message: string }>;
export type VerificationFailure = 'obsolete' | 'inventory' | 'length' | 'digest' | 'digest-unavailable';
export type FailureEvidence = Readonly<{ kind: 'protocol'; failure: ArtifactClientFailure }>
  | Readonly<{ kind: 'input'; reason: ArtifactInputFailure }>
  | Readonly<{ kind: 'verification'; reason: VerificationFailure }>
  | Readonly<{ kind: 'other'; message: BoundedText }>;
export type MeasuredBytes = Readonly<{ byteLength: ByteCount; sha256: Sha256 }>;
export type MeasuredText = Readonly<{ utf16Length: Utf16Length; utf8: MeasuredBytes }>;
export type PreviewEvidence = Readonly<{ kind: 'text' | 'text-prefix'; text: MeasuredText }>
  | Readonly<{ kind: 'binary'; prefix: MeasuredBytes }>
  | Readonly<{ kind: 'invalid-utf8' }>;
export type OwnedFileEvidence = Readonly<{ id: FileAlias; path: string; declaredKind: 'utf8-text' | 'binary'; bytes: MeasuredBytes; preview: PreviewEvidence }>;
export type FileByteEvidence = Readonly<{ path: string; bytes: MeasuredBytes }>;
/** Entries measured after independently parsing actual production ZIP bytes.
 * ZIP byte length is bounded evidence; compression/member encoding need not be
 * byte-identical across implementations. Entry names/content are exact.
 */
export type ArchiveEvidence = Readonly<{ encodedByteLength: ByteCount; entries: readonly FileByteEvidence[] }>;
export type TransferPhase = 'captured' | 'connecting' | 'initializing' | 'generating' | 'receiving' | 'verifying' | 'releasing' | 'finished';
export type RunResult = Readonly<{ kind: 'verified'; manifest: ManifestBinding; inventory: readonly OwnedFileEvidence[]; cleanup: ArtifactCleanup }>
  | Readonly<{ kind: 'generation-failed'; diagnostics: readonly Diagnostic[]; cleanup: ArtifactCleanup }>
  | Readonly<{ kind: 'failed'; failure: FailureEvidence; cleanup: ArtifactCleanup }>
  | Readonly<{ kind: 'discarded'; cleanup: ArtifactCleanup }>;
export type TerminalSummary = Readonly<{ kind: 'pending' }> | Readonly<{ kind: 'construction-refused' }>
  | Readonly<{ kind: 'verified' | 'generation-failed' | 'failed' | 'discarded'; cleanup: ArtifactCleanup }>;
export type CountsByEffectKind = Readonly<Record<EffectKind, ExactCount>>;
export type ConnectArgument = Readonly<{ signalAborted: boolean }>;
export type WireArgument = Readonly<{ frame: FrameSource }>;
export type ClientEvent = Readonly<{ kind: 'effect'; attempt: AttemptId; index: EffectIndex; effect: 'connect'; argument: ConnectArgument }>
  | Readonly<{ kind: 'effect'; attempt: AttemptId; index: EffectIndex; effect: 'initialize' | 'generate' | 'read' | 'release'; argument: WireArgument }>
  | Readonly<{ kind: 'effect'; attempt: AttemptId; index: EffectIndex; effect: 'digest'; argument: MeasuredBytes }>
  | Readonly<{ kind: 'settled'; attempt: AttemptId; index: EffectIndex; settlement: 'resolved' | 'rejected' }>
  | Readonly<{ kind: 'close'; attempt: AttemptId }>
  | Readonly<{ kind: 'cancel-result'; attempt: AttemptId; cleanup: ArtifactCleanup }>;
export type ViewEvidence = Readonly<{
  file: FileAlias; path: string; binary: boolean; encoding: 'verified-bytes'; byteLength: ByteCount;
  previewState: 'text' | 'text-prefix' | 'binary' | 'invalid-utf8'; content: MeasuredText;
  binaryPreview: MeasuredBytes | null; reference: Readonly<{ views: ViewId; file: FileAlias }>;
}>;
export type ActionResult = Readonly<{ kind: 'none' }>
  | Readonly<{ kind: 'published'; views: ViewId; artifacts: readonly ViewEvidence[] }>
  | Readonly<{ kind: 'download'; files: readonly FileByteEvidence[] }>
  | Readonly<{ kind: 'archive'; archive: ArchiveEvidence }>
  | Readonly<{ kind: 'refused'; operation: 'publish' | 'download' | 'archive' | 'mutate-copy'; message: BoundedText }>;
export type AttemptCheckpoint = Readonly<{
  id: AttemptId; phase: TransferPhase | 'not-started' | 'construction-refused';
  pending: readonly Readonly<{ index: EffectIndex; effect: EffectKind }>[];
  signalAborted: boolean | null; terminal: TerminalSummary; closeCalls: ExactCount;
}>;
export type ClientCheckpoint = Readonly<{
  actionIndex: ActionIndex; eventCount: ExactCount; label: ObservationLabel | null; currentContext: LocalContext | null;
  attempts: readonly AttemptCheckpoint[];
  registry: Readonly<{ kind: 'empty' }> | Readonly<{ kind: 'published'; views: ViewId }>;
  actionResult: ActionResult;
}>;
export type AttemptEvidence = Readonly<{
  id: AttemptId; capture: CapturedBinding | null;
  phase: TransferPhase | 'construction-refused';
  result: RunResult | Readonly<{ kind: 'construction-refused'; failure: FailureEvidence }>;
  closeCalls: ExactCount; effects: CountsByEffectKind;
}>;
export type ClientEvidence = Readonly<{ events: readonly ClientEvent[]; checkpoints: readonly ClientCheckpoint[]; attempts: readonly AttemptEvidence[] }>;
