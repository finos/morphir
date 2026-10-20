//! Proposed new child of the existing adapter_selection test module.
//! Existing literal selector and all old tests stay unchanged.
use super::*;
use morphir_mck::workbench::RunConfiguration;
use std::ffi::{OsStr, OsString};

#[test]
fn installed_configuration_uses_the_existing_literal_builtin_selector_only() {
    let policy = RunConfiguration::from_json(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../morphir-mck/src/workbench/installed_borrowed_controls/installed-policy.json"
    )))
    .unwrap();
    assert!(policy.installed_observation_limits().is_some());
    assert!(policy.native_observation_limits().is_some());
    assert_eq!(
        WorkbenchAdapter::parse(OsStr::new("builtin:morphir-workbench"), &[]),
        Ok(WorkbenchAdapter::BuiltinNativeWorkbench)
    );
    assert!(matches!(
        WorkbenchAdapter::parse(OsStr::new("builtin:morphir-workbench-installed"), &[]),
        Ok(WorkbenchAdapter::External { .. })
    ));
}

#[test]
fn installed_launch_inputs_cannot_enter_through_builtin_adapter_arguments() {
    let arguments = [OsString::from("/explicit/artifact-inputs.json")];
    assert_eq!(
        WorkbenchAdapter::parse(OsStr::new("builtin:morphir-workbench"), &arguments),
        Err(AdapterSelectionError::BuiltinArguments)
    );
}
