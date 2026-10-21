//! Prospective child of existing installed_launch::tests. Lexical only.
//! Reuses its unchanged RunArgs parsing helpers and existing legacy controls.
use super::*;

fn browser_mode() -> WorkbenchExecutionMode {
    WorkbenchExecutionMode::BrowserOriginals
}

#[test]
fn browser_selection_01_closed_builtin_only_without_installed_flags_or_free_arguments() {
    assert!(matches!(
        WorkbenchLaunch::select(&args(&[]), browser_mode()),
        Ok(WorkbenchLaunch::BrowserOriginals)
    ));
    for target in ["node", "native"] {
        assert!(WorkbenchLaunch::select(&args(&options(target)), browser_mode()).is_err());
    }
    let mut with_arguments = args(&[]);
    with_arguments.adapter_args.push("arbitrary-wrapper".into());
    assert!(WorkbenchLaunch::select(&with_arguments, browser_mode()).is_err());
    let external = Arguments::try_parse_from(base_argv("external-browser-wrapper"))
        .unwrap()
        .run;
    assert!(WorkbenchLaunch::select(&external, browser_mode()).is_err());
    // Retain native and historical routing, independently of browser selection.
    assert!(matches!(
        WorkbenchLaunch::select(&args(&[]), mode(NATIVE)),
        Ok(WorkbenchLaunch::NativeHost)
    ));
    assert!(matches!(
        WorkbenchLaunch::select(&external, mode(r#"{"kind":"historical"}"#)),
        Ok(WorkbenchLaunch::External { .. })
    ));
}
