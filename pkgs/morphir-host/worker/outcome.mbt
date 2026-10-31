///|
/// The host's failure and refusal codes.
pub(all) enum FailureCode {
  IncompleteSession
  FrameInvalid
  UnexpectedResponse
  ResponseLimit
  RequestLimit
  ProtocolUnavailable
  TupleUnavailable
  AgreementMismatch
  DescribeFailed
  ClaimsMismatch
  CapabilityUnavailable
  PlatformMismatch
  RuntimeUnavailable
  DigestMismatch
  AbiUnsupported
  AbiMismatch
  WasmFeatureUnsupported
  MemoryLimit
  GuestTrap
  TreeTerminationFailed
  BudgetExhausted
  WorkerRuntimeMismatch
} derive(Eq, Debug)

///|
pub extend FailureCode with Eq::{equal, not_equal}

///|
pub extend FailureCode with @debug.Debug::{to_repr}

///|
pub impl Show for FailureCode with fn output(self, logger) {
  logger.write_string(
    match self {
      IncompleteSession => "extension.incomplete_session"
      FrameInvalid => "extension.frame_invalid"
      UnexpectedResponse => "extension.unexpected_response"
      ResponseLimit => "extension.response_limit"
      RequestLimit => "extension.request_limit"
      ProtocolUnavailable => "extension.protocol_unavailable"
      TupleUnavailable => "extension.tuple_unavailable"
      AgreementMismatch => "extension.agreement_mismatch"
      DescribeFailed => "extension.describe_failed"
      ClaimsMismatch => "extension.claims_mismatch"
      CapabilityUnavailable => "extension.capability_unavailable"
      PlatformMismatch => "extension.platform_mismatch"
      RuntimeUnavailable => "extension.runtime_unavailable"
      DigestMismatch => "extension.digest_mismatch"
      AbiUnsupported => "extension.abi_unsupported"
      AbiMismatch => "extension.abi_mismatch"
      WasmFeatureUnsupported => "extension.wasm_feature_unsupported"
      MemoryLimit => "extension.memory_limit"
      GuestTrap => "extension.guest_trap"
      TreeTerminationFailed => "execution.tree_termination_failed"
      BudgetExhausted => "extension.budget_exhausted"
      WorkerRuntimeMismatch => "extension.worker_runtime_mismatch"
    },
  )
}

///|
pub extend FailureCode with Show::{to_string, output}

///|
/// A code for a check that failed before any operation was sent.
pub(all) enum RefusalCode {
  RequestLimit
  ProtocolUnavailable
  TupleUnavailable
  AgreementMismatch
  ClaimsMismatch
  CapabilityUnavailable
  PlatformMismatch
  RuntimeUnavailable
  DigestMismatch
  AbiUnsupported
  AbiMismatch
  WasmFeatureUnsupported
  WorkerRuntimeMismatch
} derive(Eq, Debug)

///|
pub extend RefusalCode with Eq::{equal, not_equal}

///|
pub extend RefusalCode with @debug.Debug::{to_repr}

///|
pub fn RefusalCode::code(self : RefusalCode) -> FailureCode {
  match self {
    RequestLimit => RequestLimit
    ProtocolUnavailable => ProtocolUnavailable
    TupleUnavailable => TupleUnavailable
    AgreementMismatch => AgreementMismatch
    ClaimsMismatch => ClaimsMismatch
    CapabilityUnavailable => CapabilityUnavailable
    PlatformMismatch => PlatformMismatch
    RuntimeUnavailable => RuntimeUnavailable
    DigestMismatch => DigestMismatch
    AbiUnsupported => AbiUnsupported
    AbiMismatch => AbiMismatch
    WasmFeatureUnsupported => WasmFeatureUnsupported
    WorkerRuntimeMismatch => WorkerRuntimeMismatch
  }
}

///|
pub impl Show for RefusalCode with fn output(self, logger) {
  self.code().output(logger)
}

///|
pub extend RefusalCode with Show::{to_string, output}

///|
/// A code for a protocol, transport or worker fault.
pub(all) enum FaultCode {
  IncompleteSession
  FrameInvalid
  UnexpectedResponse
  ResponseLimit
  DescribeFailed
  MemoryLimit
  GuestTrap
  TreeTerminationFailed
  BudgetExhausted
} derive(Eq, Debug)

///|
pub extend FaultCode with Eq::{equal, not_equal}

///|
pub extend FaultCode with @debug.Debug::{to_repr}

///|
pub fn FaultCode::code(self : FaultCode) -> FailureCode {
  match self {
    IncompleteSession => IncompleteSession
    FrameInvalid => FrameInvalid
    UnexpectedResponse => UnexpectedResponse
    ResponseLimit => ResponseLimit
    DescribeFailed => DescribeFailed
    MemoryLimit => MemoryLimit
    GuestTrap => GuestTrap
    TreeTerminationFailed => TreeTerminationFailed
    BudgetExhausted => BudgetExhausted
  }
}

///|
pub impl Show for FaultCode with fn output(self, logger) {
  self.code().output(logger)
}

///|
pub extend FaultCode with Show::{to_string, output}

///|
/// Why a session failed: a host check found a fault, or the guest returned a
/// JSON-RPC error, with its optional `data` member kept as sent.
pub(all) enum Fault {
  Host(code~ : FaultCode, message~ : String)
  Guest(code~ : Int32, message~ : String, data~ : Json?)
} derive(Eq, Debug)

///|
pub extend Fault with Eq::{equal, not_equal}

///|
pub extend Fault with @debug.Debug::{to_repr}

///|
let stderr_tail_bytes : Int32 = 65536

///|
/// The last 64 KiB of a worker's stderr, kept as diagnostics. `truncated`
/// reports that earlier bytes were dropped.
pub struct StderrTail {
  priv data : Bytes
  priv dropped : Bool
} derive(Eq, Debug)

///|
pub extend StderrTail with Eq::{equal, not_equal}

///|
pub extend StderrTail with @debug.Debug::{to_repr}

///|
pub fn StderrTail::empty() -> StderrTail {
  { data: b"", dropped: false, }
}

///|
pub fn StderrTail::of(bytes : Bytes) -> StderrTail {
  let start = @cmp.maximum(0, bytes.length() - stderr_tail_bytes)
  { data: bytes[start:].to_owned(), dropped: start > 0, }
}

///|
pub fn StderrTail::bytes(self : StderrTail) -> Bytes {
  self.data
}

///|
pub fn StderrTail::truncated(self : StderrTail) -> Bool {
  self.dropped
}

///|
/// The class of a finished session. `Unsuccessful` is a guest answer with
/// `success: false`; `Refused` is a check that failed before any operation;
/// `Failed` is a protocol, transport or worker fault.
pub(all) enum OutcomeClass[T] {
  Completed(T)
  Unsuccessful
  Failed(Fault)
  Refused(code~ : RefusalCode, message~ : String)
  Deadline
  Cancelled
} derive(Eq, Debug)

///|
pub extend OutcomeClass with Eq::{equal, not_equal}

///|
pub extend OutcomeClass with @debug.Debug::{to_repr}

///|
/// A session result. Every class keeps the guest's diagnostics and stderr tail.
pub struct Outcome[T] {
  class : OutcomeClass[T]
  diagnostics : Array[Diagnostic]
  stderr : StderrTail
} derive(Eq, Debug)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with @debug.Debug::{to_repr}

///|
pub fn[T] Outcome::new(
  class : OutcomeClass[T],
  diagnostics~ : ArrayView[Diagnostic],
  stderr~ : StderrTail,
) -> Outcome[T] {
  { class, diagnostics: diagnostics.to_owned(), stderr, }
}

///|
/// The same outcome with the value of a completed class changed.
pub fn[T, U] Outcome::map(self : Outcome[T], f : (T) -> U) -> Outcome[U] {
  {
    class: match self.class {
      Completed(value) => Completed(f(value))
      Unsuccessful => Unsuccessful
      Failed(fault) => Failed(fault)
      Refused(code~, message~) => Refused(code~, message~)
      Deadline => Deadline
      Cancelled => Cancelled
    },
    diagnostics: self.diagnostics,
    stderr: self.stderr,
  }
}
