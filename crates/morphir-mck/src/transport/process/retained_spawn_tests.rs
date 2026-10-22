//! Actual pre-child spawn refusal must return the SAME caller capture backing.
use super::*;

#[test]
fn fixed_capture_retained_spawn_01_missing_executable_returns_actual_backing() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    let limits = Limits {
        max_frame: 64,
        stderr_capture: 32,
        ..Limits::DEFAULT
    };
    let stdout = Vec::with_capacity(97);
    let stderr = Vec::with_capacity(53);
    let pointers = [stdout.as_ptr(), stderr.as_ptr()];
    let capacities = [stdout.capacity(), stderr.capacity()];
    let capture = FixedCaptureBuffers::new(stdout, stderr);
    let spec = CommandSpec::new(
        root.join("genuinely-absent-executable"),
        vec![],
        root,
        vec![],
    )
    .unwrap();
    let failure = match OneShotProcess::spawn_fixed_capture_retained(spec, limits, capture) {
        Err(failure) => failure,
        Ok(_) => panic!("a missing executable cannot create a retained process owner"),
    };
    let (cause, capture) = failure.into_parts();
    assert!(
        matches!(cause, InteractiveSpawnError::Process(ProcessError::Spawn(ref error))
        if error.kind() == io::ErrorKind::NotFound)
    );
    assert_eq!([capture.stdout.as_ptr(), capture.stderr.as_ptr()], pointers);
    assert_eq!(
        [capture.stdout.capacity(), capture.stderr.capacity()],
        capacities
    );
    assert!(capture.stdout.is_empty());
    assert!(capture.stderr.is_empty());
}

#[test]
fn fixed_capture_retained_spawn_02_piped_missing_executable_returns_actual_backing() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    let limits = Limits {
        max_frame: 64,
        stderr_capture: 32,
        ..Limits::DEFAULT
    };
    let stdout = Vec::with_capacity(97);
    let stderr = Vec::with_capacity(53);
    let pointers = [stdout.as_ptr(), stderr.as_ptr()];
    let capacities = [stdout.capacity(), stderr.capacity()];
    let capture = FixedCaptureBuffers::new(stdout, stderr);
    let spec = CommandSpec::new(
        root.join("genuinely-absent-piped-executable"),
        vec![],
        root,
        vec![],
    )
    .unwrap();
    let failure = match InteractiveProcess::spawn_retained(spec, limits, capture) {
        Err(failure) => failure,
        Ok(_) => panic!("a missing piped executable cannot create a retained process owner"),
    };
    let (cause, capture) = failure.into_parts();
    assert!(
        matches!(cause, InteractiveSpawnError::Process(ProcessError::Spawn(ref error))
        if error.kind() == io::ErrorKind::NotFound)
    );
    assert_eq!([capture.stdout.as_ptr(), capture.stderr.as_ptr()], pointers);
    assert_eq!(
        [capture.stdout.capacity(), capture.stderr.capacity()],
        capacities
    );
    assert!(capture.stdout.is_empty());
    assert!(capture.stderr.is_empty());
}
