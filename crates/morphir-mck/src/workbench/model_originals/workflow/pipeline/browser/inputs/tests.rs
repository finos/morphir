//! Prospective child of pipeline::browser::inputs. No browser/process/report.
//! Private field checks here are not part of the callback interface.
use super::*;
use crate::workbench::configuration::BrowserClient;
use crate::workbench::corpus::CorpusSource;
use crate::workbench::model_originals::workflow::scope::SourcePosition;
use crate::workbench::model_originals::workflow::{
    compile::CompileError,
    decode::{DecodeError, OperandResource},
    expansion::{ExpansionError, ExpansionResource},
    ingress::IngressError,
    pipeline::PreparationFault,
    source_compile::CompilationError,
    source_proof::SourceError,
    work::{ClosureError, Resource},
};
use crate::workbench::model_originals::workflow::{
    compile::DefinitionOrigin,
    meaning::Role,
    pairing::PairedRun,
    pipeline::{
        Source,
        browser::{BrowserPreparationFault, prepared_browser_originals},
    },
};
use crate::workbench::{RunConfiguration, WorkbenchExecutionMode};
use std::cell::Cell;

const CORPUS: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
));
const CHECKER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
));
const FORGED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/source-forged-cases.json"
));
const REORDERED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/reordered-cases.json"
));

fn configuration_with(checker: serde_json::Value, retained: u64) -> RunConfiguration {
    // Test-only caller configuration construction, never production parsing.
    RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving":{"retainedBytes":retained,"stdoutPrefixBytes":0,
                "stderrPrefixBytes":0,"snapshotReadBytes":4096,"byteVisits":1048576,"records":0}
        })
        .to_string(),
    )
    .unwrap()
}
fn configuration() -> RunConfiguration {
    configuration_with(serde_json::from_str(CHECKER).unwrap(), 1048576)
}
fn source(raw: &str) -> Source {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), raw).unwrap();
    Source::new(CorpusSource::load(root.path()).unwrap()).unwrap()
}

#[test]
fn browser_inputs_01_full_preparation_then_same_borrowed_inputs_and_alias_filter() {
    let calls = Cell::new(0);
    let source = source(CORPUS);
    prepared_browser_originals::<_, BrowserInputFault>(&source, &configuration(), |inventory, loans| {
        calls.set(calls.get() + 1);
        // Current source inventory only, never a role budget or qualification.
        assert_eq!(inventory.case_count(), 23);
        assert_eq!(inventory.compiled.len(), source.case_count());
        let required_clients = inventory.compiled.iter().filter(|row| row.current()
            .is_some_and(|core| matches!(core.source().paired().run(), PairedRun::Client { .. }))).count();
        let mut clients = 0;
        let mut expected_definitions = 0;
        let mut archive_actions = 0;
        inventory.visit_clients(loans, |client, loans| {
            clients += 1;
            let core = inventory.compiled[client.case_index()].current().unwrap();
            assert!(std::ptr::eq(client.core, core));
            assert!(std::ptr::eq(core.expansion().scenario(), core.source().paired().scenario()));
            assert_eq!(client.run_index(), core.source().paired().run_index());
            let PairedRun::Client { actions, fixture } = core.source().paired().run() else {
                panic!("only the existing compiled client role is lent")
            };
            assert!(std::ptr::eq(client.fixture().input, fixture));
            let projected = client.actions(loans).unwrap();
            assert_eq!(projected.len(), actions.len());
            for (position, (view, input)) in projected.zip(actions).enumerate() {
                assert_eq!(view.position(), position);
                assert!(std::ptr::eq(view.input, input));
                match (view.kind(), input) {
                    (BrowserActionKind::StartConnected { attempt, .. },
                        crate::workbench::model_originals::workflow::input::ClientAction::StartConnected { attempt: actual, .. }) => assert!(std::ptr::eq(attempt, actual)),
                    (BrowserActionKind::BindModelOwner { model, .. },
                        crate::workbench::model_originals::workflow::input::ClientAction::BindModelOwner { model: actual, .. }) => assert!(std::ptr::eq(model, actual)),
                    (BrowserActionKind::DownloadArchive { model },
                        crate::workbench::model_originals::workflow::input::ClientAction::DownloadArchive { model: actual }) => {
                        assert!(std::ptr::eq(model, actual)); archive_actions += 1;
                    }
                    (BrowserActionKind::DownloadOriginal { .. }, crate::workbench::model_originals::workflow::input::ClientAction::DownloadOriginal { .. })
                    | (BrowserActionKind::CloseModel { .. }, crate::workbench::model_originals::workflow::input::ClientAction::CloseModel { .. })
                    | (BrowserActionKind::CloseCurrentModel, crate::workbench::model_originals::workflow::input::ClientAction::CloseCurrentModel { .. })
                    | (BrowserActionKind::Checkpoint { .. }, crate::workbench::model_originals::workflow::input::ClientAction::Checkpoint { .. }) => {},
                    (BrowserActionKind::Unsupported, input) => assert!(!matches!(input,
                        crate::workbench::model_originals::workflow::input::ClientAction::StartConnected { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::BindModelOwner { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::DownloadOriginal { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::DownloadArchive { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::CloseModel { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::CloseCurrentModel { .. }
                        | crate::workbench::model_originals::workflow::input::ClientAction::Checkpoint { .. })),
                    _ => panic!("closed projection must agree with this exact input variant"),
                }
            }
            let aliases: Vec<_> = client.input_aliases(loans).unwrap().collect();
            let required_aliases = core.aliases().definitions().iter().filter(|d|
                d.origin == DefinitionOrigin::Input && matches!(d.role,
                    Role::Model | Role::OpeningAttempt | Role::LiteralPeer | Role::File | Role::Checkpoint)).count();
            assert_eq!(aliases.len(), required_aliases);
            for alias in aliases {
                assert_eq!(alias.definition.origin, DefinitionOrigin::Input);
                assert!(matches!(alias.definition.position, SourcePosition::Fixture | SourcePosition::Action(_)));
                assert!(core.aliases().definitions().iter().any(|d| std::ptr::eq(d, alias.definition)));
                assert!(core.aliases().definitions().iter().filter(|d| d.origin != DefinitionOrigin::Input)
                    .all(|d| !std::ptr::eq(d, alias.definition)));
                assert!(matches!((alias.kind(), alias.definition.role),
                    (BrowserInputAliasKind::Model, Role::Model)
                    | (BrowserInputAliasKind::OpeningAttempt, Role::OpeningAttempt)
                    | (BrowserInputAliasKind::LiteralPeer, Role::LiteralPeer)
                    | (BrowserInputAliasKind::File, Role::File)
                    | (BrowserInputAliasKind::Checkpoint, Role::Checkpoint)));
            }
            expected_definitions += core.aliases().definitions().iter()
                .filter(|d| d.origin == DefinitionOrigin::Expected).count();
            Ok(())
        })?;
        assert_eq!(clients, required_clients);
        assert!(clients > 0 && archive_actions > 0 && expected_definitions > 0);
        assert!(loans.owners.closure.usage().definitions > 0);
        assert!(loans.owners.closure.usage().references > 0);
        Ok(())
    }).unwrap();
    assert_eq!(calls.get(), 1);
}

#[test]
fn browser_inputs_02_whole_forged_reordered_and_prefix_sources_refuse_before_callback() {
    #[derive(serde::Serialize, serde::Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct CorpusMutation {
        format_version: Box<serde_json::value::RawValue>,
        cases: Vec<Box<serde_json::value::RawValue>>,
    }
    let mut prefix: CorpusMutation = serde_json::from_str(CORPUS).unwrap();
    prefix.cases.pop();
    let prefix = serde_json::to_string(&prefix).unwrap();
    enum Refusal {
        MissingManifest,
        Inventory,
    }
    for (raw, cause) in [
        (FORGED, Refusal::MissingManifest),
        (REORDERED, Refusal::Inventory),
        (&prefix, Refusal::Inventory),
    ] {
        let calls = Cell::new(0);
        let result = prepared_browser_originals::<_, BrowserInputFault>(
            &source(raw),
            &configuration(),
            |_, _| {
                calls.set(calls.get() + 1);
                Ok(())
            },
        );
        match cause {
            Refusal::MissingManifest => assert!(matches!(
                result,
                Err(BrowserPreparationFault::Preparation(
                    PreparationFault::Compilation(CompilationError::Source(
                        SourceError::MissingManifestCase
                    ))
                ))
            )),
            Refusal::Inventory => assert!(matches!(
                result,
                Err(BrowserPreparationFault::Preparation(
                    PreparationFault::Compilation(CompilationError::Source(SourceError::Inventory))
                ))
            )),
        }
        assert_eq!(calls.get(), 0);
    }
}

#[test]
fn browser_inputs_03_same_closure_and_expansion_refusal_precede_callback() {
    enum Refusal {
        Closure,
        Expansion,
        Decode,
    }
    for (section, field, value, cause) in [
        ("closure", "definitions", 0, Refusal::Closure),
        ("expansion", "frameBytes", 0, Refusal::Expansion),
        ("decode", "byteVisits", 1, Refusal::Decode),
    ] {
        let mut checker: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
        checker[section][field] = value.into();
        let calls = Cell::new(0);
        let result = prepared_browser_originals::<_, BrowserInputFault>(
            &source(CORPUS),
            &configuration_with(checker, 1048576),
            |_, _| {
                calls.set(calls.get() + 1);
                Ok(())
            },
        );
        match cause {
            Refusal::Closure => assert!(matches!(
                result,
                Err(BrowserPreparationFault::Preparation(
                    PreparationFault::Compilation(CompilationError::Closure(CompileError::Owner(
                        ClosureError::Resource(Resource::Definitions)
                    )))
                ))
            )),
            Refusal::Expansion => assert!(matches!(
                result,
                Err(BrowserPreparationFault::Preparation(
                    PreparationFault::Compilation(CompilationError::Expansion(
                        ExpansionError::Resource(ExpansionResource::FrameBytes)
                    ))
                ))
            )),
            Refusal::Decode => assert!(matches!(
                result,
                Err(BrowserPreparationFault::Preparation(
                    PreparationFault::Ingress(IngressError::Decode(DecodeError::Work(
                        OperandResource::ByteVisits
                    )))
                ))
            )),
        }
        assert_eq!(calls.get(), 0);
    }
}

#[test]
fn browser_inputs_04_one_receiving_loan_is_sticky_without_new_preparation_credit() {
    use crate::workbench::model_originals::workflow::pipeline::installed::observation::{
        InstalledObservationFault, InstalledObservationResource,
    };
    let configuration = configuration_with(serde_json::from_str(CHECKER).unwrap(), 0);
    prepared_browser_originals::<_, BrowserInputFault>(&source(CORPUS), &configuration, |inventory, loans| {
        let decoder = std::ptr::from_ref(&loans.owners.decode);
        let comparison = std::ptr::from_ref(&loans.owners.comparison);
        let receiving = std::ptr::from_ref(&*loans.receiving);
        let fault = loans
            .receiving
            .reserve_span(InstalledObservationResource::RetainedBytes, 1)
            .unwrap_err();
        assert!(matches!(
            fault,
            InstalledObservationFault::Resource {
                kind: InstalledObservationResource::RetainedBytes,
                limit: 0,
                used: 0,
                requested: 1
            }
        ));
        let before = (
            loans.owners.decode.usage(),
            loans.owners.closure.usage(),
            loans.receiving.usage(),
            loans.owners.comparison.usage(),
        );
        let result = inventory.visit_clients(loans, |_, _| {
            panic!("no callback after prior receiving fault")
        });
        assert!(result.is_err());
        assert!(
            matches!(loans.ready(), Err(BrowserInputFault::Receiving(actual)) if actual == fault)
        );
        assert_eq!(
            before,
            (
                loans.owners.decode.usage(),
                loans.owners.closure.usage(),
                loans.receiving.usage(),
                loans.owners.comparison.usage()
            )
        );
        assert_eq!(decoder, std::ptr::from_ref(&loans.owners.decode));
        assert_eq!(comparison, std::ptr::from_ref(&loans.owners.comparison));
        assert_eq!(receiving, std::ptr::from_ref(&*loans.receiving));
        Ok(())
    })
    .unwrap();
}

#[test]
fn browser_inputs_05_browser_policy_is_closed_explicit_and_has_no_protocol_version_or_rpc_grant() {
    assert_eq!(
        configuration().execution_mode(),
        WorkbenchExecutionMode::BrowserOriginals
    );
    assert_eq!(
        configuration().browser_client(),
        Some(BrowserClient::Chromium)
    );
    let configuration = configuration();
    let limits = configuration.browser_receiving_limits().unwrap();
    assert_eq!(limits.retained_bytes(), 1048576);
    assert_eq!(limits.stdout_prefix_bytes(), 0);
    assert_eq!(limits.stderr_prefix_bytes(), 0);
    assert_eq!(limits.snapshot_read_bytes(), 4096);
    assert_eq!(limits.byte_visits(), 1048576);
    assert_eq!(limits.records(), 0);
    let checker: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
    let good = serde_json::json!({"kind":"model-originals-browser", "browser":"chromium", "checker":checker,
        "receiving":{"retainedBytes":0,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":0,"records":0}});
    assert!(RunConfiguration::from_json(&good.to_string()).is_ok());
    for field in ["checker", "browser", "receiving"] {
        let mut bad = good.clone();
        bad.as_object_mut().unwrap().remove(field);
        assert!(RunConfiguration::from_json(&bad.to_string()).is_err());
    }
    for (field, value) in [("version", "1"), ("browser", "proton")] {
        let mut bad = good.clone();
        bad[field] = value.into();
        assert!(RunConfiguration::from_json(&bad.to_string()).is_err());
    }
    for (field, value) in [
        ("rpcFrames", serde_json::json!("checker-capture")),
        ("retainedBytes", serde_json::json!(1.5)),
        ("records", serde_json::json!(-1)),
    ] {
        let mut bad = good.clone();
        bad["receiving"][field] = value;
        assert!(RunConfiguration::from_json(&bad.to_string()).is_err());
    }
    let duplicate = good.to_string().replacen(
        "\"browser\":\"chromium\"",
        "\"browser\":\"chromium\",\"browser\":\"chromium\"",
        1,
    );
    assert!(RunConfiguration::from_json(&duplicate).is_err());
    assert!(RunConfiguration::from_json(r#"{"kind":"historical"}"#).is_ok());
    assert!(RunConfiguration::from_json(CHECKER).is_ok());
}

#[test]
fn browser_inputs_06_generic_session_factory_cannot_select_or_launch_browser_mode() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CORPUS).unwrap();
    let calls = Cell::new(0);
    let result = crate::workbench::run_configured_with_session_factory(
        root.path(),
        &configuration(),
        || {
            calls.set(calls.get() + 1);
            panic!("generic Session factory is not a maintained browser owner")
        },
    );
    assert!(result.is_err());
    assert_eq!(calls.get(), 0);
}

#[test]
fn browser_inputs_07_callback_error_is_retained_as_its_closed_type() {
    #[derive(Debug)]
    enum CallbackFault {
        Stop,
    }
    let calls = Cell::new(0);
    let result = prepared_browser_originals(&source(CORPUS), &configuration(), |_, _| {
        calls.set(calls.get() + 1);
        Err::<(), _>(CallbackFault::Stop)
    });
    assert!(matches!(
        result,
        Err(BrowserPreparationFault::Preparation(
            PreparationFault::Callback(CallbackFault::Stop)
        ))
    ));
    assert_eq!(calls.get(), 1);
}

mod projections;
