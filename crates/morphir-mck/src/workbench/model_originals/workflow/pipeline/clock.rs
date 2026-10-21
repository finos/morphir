//! Shared qualified-Darwin sampling. No invocation, runtime or source authority.
pub(in crate::workbench::model_originals::workflow) mod deadline;
#[cfg(target_os = "macos")]
use std::time::Instant;
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn mach_continuous_time() -> u64;
    fn mach_timebase_info(info: *mut MachTimebase) -> i32;
}
#[repr(C)]
#[cfg(target_os = "macos")]
struct MachTimebase {
    numer: u32,
    denom: u32,
}
#[cfg(target_os = "macos")]
pub(super) fn sample()
-> Result<(Instant, u64, Instant, deadline::Timebase), deadline::DeadlineError> {
    let mut ratio = MachTimebase { numer: 0, denom: 0 };
    // SDK C layout/calls, identical to the prior consumer-local sampler.
    if unsafe { mach_timebase_info(&mut ratio) } != 0 {
        return Err(deadline::DeadlineError::InvalidTimebase);
    }
    let timebase = deadline::Timebase::new(ratio.numer, ratio.denom)?;
    let before = Instant::now();
    let ticks = unsafe { mach_continuous_time() };
    let after = Instant::now();
    Ok((before, ticks, after, timebase))
}
