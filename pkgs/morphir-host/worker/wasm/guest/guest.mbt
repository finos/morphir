///|
/// What a guest gave for one message: a response, nothing for a notification,
/// or the end of the guest after `exit`.
pub(all) enum Reply {
  Response(Bytes)
  Notified
  Exit
} derive(Eq, Debug)

///|
pub extend Reply with Eq::{equal, not_equal}

///|
pub extend Reply with @debug.Debug::{to_repr}

///|
/// A guest stopped serving for a fault. The guest takes no more messages.
pub(all) suberror GuestError {
  Faulted(@worker.GuestFault)
} derive(Eq, Debug)

///|
pub extend GuestError with Eq::{equal, not_equal}

///|
pub extend GuestError with @debug.Debug::{to_repr}

///|
/// One WASM guest instance that serves whole MEP messages, one at a time.
pub(open) trait Guest {
  fn exchange(Self, Bytes) -> Reply raise GuestError
}

///|
/// The bounds of one guest call: a deadline, and an instruction budget where
/// the engine meters instructions.
pub struct CallBounds {
  deadline_ms : Int32
  instructions : Int32?
} derive(Eq, Debug)

///|
pub extend CallBounds with Eq::{equal, not_equal}

///|
pub extend CallBounds with @debug.Debug::{to_repr}

///|
pub fn CallBounds::new(
  deadline_ms~ : Int32,
  instructions~ : Int32?,
) -> CallBounds {
  { deadline_ms, instructions, }
}

///|
/// The bounds of each call for an ABI profile: 30 seconds for
/// `extism-kernel-v1` and 10 seconds for `morphir-bytes-v1`, with a budget of
/// 1,000,000,000 instructions.
pub fn CallBounds::for_abi(abi : @worker.WasmAbi) -> CallBounds {
  let profile = @worker.ExtismProfile::restricted()
  {
    deadline_ms: match abi {
      ExtismKernelV1 => profile.call_ms
      MorphirBytesV1 => 10000
    },
    instructions: Some(profile.instructions.to_int()),
  }
}

///|
/// The engine's arguments for one call.
fn CallBounds::engine(
  self : CallBounds,
) -> (@engine.Budget?, @engine.Deadline) raise @worker.LaunchError {
  try {
    let budget = match self.instructions {
      Some(count) => Some(@engine.Budget::parse(count.to_int64()))
      None => None
    }
    (budget, @engine.Deadline::parse(self.deadline_ms))
  } catch {
    _ => raise LaunchFailed("invalid call bounds: \{@debug.to_string(self)}")
  }
}

///|
/// The bounds that the engine of this target enforces. On js the engine
/// meters no instructions and cannot stop a call; the Node worker-thread
/// launcher ends the thread at the call deadline instead.
pub fn engine_bounds() -> @worker.EnforcedBounds {
  let bounds = @engine.Engine::default().bounds()
  let enforced = (bound : @engine.Bound, gap : @worker.BoundGap) => {
    match bound {
      Enforced => @worker.Enforcement::Enforced
      NotEnforced => NotEnforced(gap)
    }
  }
  @worker.EnforcedBounds::new(
    memory_ceiling=enforced(bounds.memory, NoMemoryCeiling),
    instruction_budget=enforced(bounds.budget, NoInstructionMetering),
    call_deadline=enforced(bounds.interruption, NoCallInterruption),
  )
}

///|
/// The guest fault for an engine call error.
fn call_fault(error : @engine.CallError) -> @worker.GuestFault {
  match error {
    Trap(kind) => Trap(@debug.to_string(kind))
    BudgetExhausted => BudgetExhausted
    Interrupted => CallDeadline
    MemoryLimit => MemoryLimit("memory.grow beyond the ceiling was refused")
    Host(HostError(text)) => Failure(cut_message(text))
    Host(Exit(code)) =>
      Failure("the guest exited with code \{code} during a call")
    UnknownExport(name) => Failure("the module exports no function \{name}")
    ArgumentMismatch(name, detail) => Failure("\{name}: \{detail}")
    Unusable => Failure("the guest instance takes no more calls")
  }
}

///|
/// Compiles a prepared module with the engine. A module that needs a feature
/// the engine lacks is refused with the feature's name.
fn compile(
  engine : @engine.Engine,
  prepared : @wasm.PreparedModule,
) -> @engine.Module raise @worker.LaunchError {
  engine.compile(prepared.module_.bytes()) catch {
    FeatureUnsupported(feature) =>
      raise WasmFeatureUnsupported(feature=Some(feature.name()))
    error =>
      raise LaunchFailed(
        "the engine refused the module: \{@debug.to_string(error)}",
      )
  }
}

///|
/// The features of a module that the engine of this target lacks, from the
/// engine's pure scan, without compiling it.
pub fn missing_feature(bytes : Bytes) -> String? {
  let supported = @engine.Engine::default().features()
  let found = @engine.Feature::scan(bytes) catch { _ => return None }
  for feature in found {
    if !supported.contains(feature) {
      return Some(feature.name())
    }
  }
  None
}

///|
/// Loads a guest: classifies the module, caps its memory, compiles it and
/// instantiates it with the adapter of its profile. `call` defaults to the
/// bounds of the profile. `services` are what an Extism guest's host
/// functions see: the workspace root and the sink for its output.
pub fn load(
  bytes : Bytes,
  declared? : @worker.WasmAbi,
  call? : CallBounds,
  limits~ : @worker.Limits = @worker.Limits::host(),
  ceiling~ : @wasm.MemoryCeiling = @wasm.MemoryCeiling::restricted(),
  services~ : GuestServices = GuestServices::new(workspace_root="", output=_ => {
    ()
  }),
) -> &Guest raise @worker.LaunchError {
  let prepared = @wasm.PreparedModule::prepare(bytes, declared?, ceiling~)
  let call = call.unwrap_or(CallBounds::for_abi(prepared.abi))
  match prepared.abi {
    MorphirBytesV1 =>
      BytesGuest::load(prepared, call~, limits~, ceiling~) as &Guest
    ExtismKernelV1 =>
      ExtismGuest::load(prepared, call~, limits~, ceiling~, services~) as &Guest
  }
}
