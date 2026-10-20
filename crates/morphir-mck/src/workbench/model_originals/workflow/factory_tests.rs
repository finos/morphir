//! Additive actual Session-factory controls, frozen before factory source code.
use crate::transport::{Limits, Session};
use crate::workbench::{RunConfiguration, run_configured_with_session_factory};
use std::cell::Cell;

#[test]
fn selected_preparation_controls_actual_factory_invocation_without_issuing_contexts() {
    let temp = tempfile::tempdir().unwrap();
    let config =
        RunConfiguration::from_json(include_str!("pipeline_controls/explicit-test-policy.json"))
            .unwrap();
    let count = Cell::new(0usize);
    let program = temp.path().join("no-such-program").into_os_string();
    std::fs::write(
        temp.path().join("cases.json"),
        include_bytes!("pipeline_controls/source-forged-cases.json"),
    )
    .unwrap();
    let result = run_configured_with_session_factory(temp.path(), &config, || {
        count.set(count.get() + 1);
        Session::spawn(&program, &[], Limits::DEFAULT)
    });
    assert!(result.unwrap_err().contains("source"));
    assert_eq!(
        count.get(),
        0,
        "invalid selected source must not invoke actual factory"
    );
    std::fs::write(
        temp.path().join("cases.json"),
        include_bytes!("pipeline_controls/cases.json"),
    )
    .unwrap();
    let result = run_configured_with_session_factory(temp.path(), &config, || {
        count.set(count.get() + 1);
        Session::spawn(&program, &[], Limits::DEFAULT)
    });
    assert!(result.unwrap_err().contains("spawn"));
    assert_eq!(
        count.get(),
        1,
        "all23 genuine contexts prepare before exactly one real spawn attempt"
    );
}

#[test]
fn historical_session_factory_keeps_single_spawn_and_original_failure_report() {
    let temp = tempfile::tempdir().unwrap();
    let corpus = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/workbench/mck/cases.json"
    ));
    std::fs::write(temp.path().join("cases.json"), corpus).unwrap();
    let config = RunConfiguration::from_json(r#"{"kind":"historical"}"#).unwrap();
    let count = Cell::new(0usize);
    let program = temp.path().join("no-such-program").into_os_string();
    let report = run_configured_with_session_factory(temp.path(), &config, || {
        count.set(count.get() + 1);
        Session::spawn(&program, &[], Limits::DEFAULT)
    })
    .unwrap();
    assert_eq!(count.get(), 1);
    assert!(!report.qualified());
    crate::workbench::check_report(temp.path(), &report).unwrap();
}
