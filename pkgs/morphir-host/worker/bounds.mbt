///|
/// Why a host did not enforce a WASM bound.
pub(all) enum BoundGap {
  /// The engine does not count instructions, as on js.
  NoInstructionMetering
  /// The engine cannot stop a call that runs, and the host does not end the
  /// worker for it.
  NoCallInterruption
  /// The engine cannot cap guest memory.
  NoMemoryCeiling
} derive(Eq, Debug)

///|
pub extend BoundGap with Eq::{equal, not_equal}

///|
pub extend BoundGap with @debug.Debug::{to_repr}

///|
pub impl Show for BoundGap with fn output(self, logger) {
  logger.write_string(
    match self {
      NoInstructionMetering => "no-instruction-metering"
      NoCallInterruption => "no-call-interruption"
      NoMemoryCeiling => "no-memory-ceiling"
    },
  )
}

///|
pub extend BoundGap with Show::{to_string, output}

///|
/// Whether a host enforced one bound.
pub(all) enum Enforcement {
  Enforced
  NotEnforced(BoundGap)
} derive(Eq, Debug)

///|
pub extend Enforcement with Eq::{equal, not_equal}

///|
pub extend Enforcement with @debug.Debug::{to_repr}

///|
pub extend Enforcement with ToJson::{to_json}

///|
pub impl ToJson for Enforcement with fn to_json(self) {
  match self {
    Enforced => { "enforced": true }
    NotEnforced(gap) => { "enforced": false, "reason": gap.to_string() }
  }
}

///|
/// The WASM bounds that a worker's host enforced: the memory ceiling, the
/// instruction budget and the per-call deadline. A WASM channel states them;
/// a process channel has none.
pub struct EnforcedBounds {
  memory_ceiling : Enforcement
  instruction_budget : Enforcement
  call_deadline : Enforcement
} derive(Eq, Debug)

///|
pub extend EnforcedBounds with Eq::{equal, not_equal}

///|
pub extend EnforcedBounds with @debug.Debug::{to_repr}

///|
pub fn EnforcedBounds::new(
  memory_ceiling~ : Enforcement,
  instruction_budget~ : Enforcement,
  call_deadline~ : Enforcement,
) -> EnforcedBounds {
  { memory_ceiling, instruction_budget, call_deadline, }
}

///|
pub extend EnforcedBounds with ToJson::{to_json}

///|
pub impl ToJson for EnforcedBounds with fn to_json(self) {
  {
    "memoryCeiling": self.memory_ceiling.to_json(),
    "instructionBudget": self.instruction_budget.to_json(),
    "callDeadline": self.call_deadline.to_json(),
  }
}
