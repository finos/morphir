//! Explicit local qualification probe, not a production deadline implementation.
use super::*;
use std::time::{Duration, Instant};

#[repr(C)]
struct Timebase {
    numer: u32,
    denom: u32,
}
unsafe extern "C" {
    fn mach_timebase_info(info: *mut Timebase) -> i32;
    fn mach_continuous_time() -> u64;
    fn mach_absolute_time() -> u64;
}
fn nanoseconds(ticks: u64, ratio: &Timebase) -> u64 {
    let wide = u128::from(ticks)
        .checked_mul(u128::from(ratio.numer))
        .unwrap()
        / u128::from(ratio.denom);
    u64::try_from(wide).unwrap()
}

#[test]
#[ignore = "requires explicit absolute MORPHIR_MCK_INSTALLED_NODE; records actual Darwin clock basis"]
fn consumer_operation_selected_node_clock_basis() {
    let node = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_INSTALLED_NODE")
            .expect("explicit selected Node executable is required"),
    );
    assert!(node.is_absolute());
    let node = node.canonicalize().unwrap();
    let directory = tempfile::tempdir().unwrap();
    let mut ratio = Timebase { numer: 0, denom: 0 };
    // SAFETY: the SDK Mach function initializes this live, correctly laid out
    // mach_timebase_info_data_t; the two clock functions take no pointers.
    assert_eq!(unsafe { mach_timebase_info(&mut ratio) }, 0);
    assert_ne!(ratio.numer, 0);
    assert_ne!(ratio.denom, 0);
    let spec = CommandSpec::new(
        node,
        vec!["-p".into(), "process.hrtime.bigint().toString()".into()],
        directory.path().to_path_buf(),
        vec![],
    )
    .unwrap();
    let rust_before = Instant::now();
    // SAFETY: these SDK functions have no arguments or borrowed storage.
    let continuous_before = nanoseconds(unsafe { mach_continuous_time() }, &ratio);
    let uptime_before = nanoseconds(unsafe { mach_absolute_time() }, &ratio);
    let mut process = OneShotProcess::spawn(
        spec,
        Limits {
            max_frame: 128,
            stderr_capture: 256,
            ..Limits::DEFAULT
        },
    )
    .unwrap();
    let end = rust_before + Duration::from_secs(10);
    loop {
        match process.advance() {
            ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        process.reap_retained().unwrap();
        if matches!(process.advance(), ProcessProgress::Finished(_)) {
            break;
        }
        assert!(Instant::now() < end, "actual Node probe must finish");
        std::thread::sleep(Duration::from_millis(1));
    }
    let outcome = match process.into_finished() {
        ProcessFinish::Finished(outcome) => outcome,
        ProcessFinish::Pending(_) => {
            panic!("actual Finished state must transfer real reader joins")
        }
    };
    // SAFETY: same SDK clocks as the pre-spawn bracket above.
    let uptime_after = nanoseconds(unsafe { mach_absolute_time() }, &ratio);
    let continuous_after = nanoseconds(unsafe { mach_continuous_time() }, &ratio);
    let rust_after = Instant::now();
    let status = outcome.status().code();
    let fault = outcome.first_fault().copied();
    let stderr = outcome.stderr().to_vec();
    let raw = std::str::from_utf8(outcome.stdout()).unwrap().trim();
    let sampled: u64 = raw.parse().unwrap();
    drop(outcome);
    let in_continuous = (continuous_before..=continuous_after).contains(&sampled);
    let in_uptime = (uptime_before..=uptime_after).contains(&sampled);
    let classification = match (in_continuous, in_uptime) {
        (true, false) => "continuous-only",
        (false, true) => "uptime-only",
        (true, true) => "overlap-inconclusive",
        (false, false) => "outside-both",
    };
    println!(
        "{}",
        serde_json::json!({
            "kind":"actual-selected-node-darwin-clock-probe",
            "classification":classification,
            "timebaseNumer":ratio.numer,
            "timebaseDenom":ratio.denom,
            "continuousBefore":continuous_before.to_string(),
            "continuousAfter":continuous_after.to_string(),
            "uptimeBefore":uptime_before.to_string(),
            "uptimeAfter":uptime_after.to_string(),
            "nodeHrtime":sampled.to_string(),
            "rustBracketNanos":rust_after.duration_since(rust_before).as_nanos().to_string(),
            "directChildStatus":status,
            "actualReadersJoined":true,
        })
    );
    // Probe interpretation follows genuine process completion and reader joins.
    assert_eq!(status, Some(0));
    assert_eq!(fault, None);
    assert!(stderr.is_empty());
    assert!(in_continuous || in_uptime, "unsupported actual clock basis");
}
