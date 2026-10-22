use super::*;
use morphir_mck::workbench::{RunConfiguration, load, with_prepared_browser_clients};

fn loans<R>(
    bytes: usize,
    run: impl FnOnce(&mut morphir_mck::workbench::BrowserLoans<'_, '_>) -> R,
) -> R {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker:serde_json::Value=serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration=RunConfiguration::from_json(&serde_json::json!({"kind":"model-originals-browser","browser":"chromium","checker":checker,"receiving":{"retainedBytes":bytes,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":8388608,"records":0}}).to_string()).unwrap();
    let source = load(root.path()).unwrap();
    with_prepared_browser_clients(&source, &configuration, |_, loans| Ok::<_, ()>(run(loans)))
        .unwrap()
        .into_parts()
        .0
        .unwrap()
}

#[test]
fn browser_prepaid_auth_01_checked_dimensions_and_insufficient_storage_before_entropy() {
    assert!(matches!(
        SessionAuth::prepaid_dimensions(usize::MAX),
        Err(PrepaidAuthFault::SizeOverflow)
    ));
    loans(128, |loans| {
        let mut calls = 0;
        let result = SessionAuth::prepaid_with_entropy(loans, "controlled", |_| {
            calls += 1;
            Ok(())
        });
        assert!(matches!(result, Err(PrepaidAuthFault::Funding(_))));
        assert_eq!(calls, 0);
    });
}

#[test]
fn browser_prepaid_auth_02_same_secret_exchange_and_cookie_semantics() {
    loans(8388608, |loans| {
        let mut calls = 0;
        let actual = SessionAuth::prepaid_with_entropy(loans, "controlled", |bytes| {
            calls += 1;
            bytes.fill(if calls == 1 { 7 } else { 9 });
            Ok(())
        })
        .unwrap();
        let (auth, token, cookie) = actual.into_parts();
        let (reference, expected) = SessionAuth::from_secrets("controlled", [7; 32], [9; 32]);
        assert_eq!(calls, 2);
        assert_eq!(token, expected);
        assert_eq!(cookie, reference.session_cookie());
        assert!(!auth.exchange_launch_token("wrong"));
        assert!(auth.exchange_launch_token(&token));
        assert!(!auth.exchange_launch_token(&token));
        assert!(auth.authenticate_cookie_header(cookie.split(';').next().unwrap()));
    });
}
