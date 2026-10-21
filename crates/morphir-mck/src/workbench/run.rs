use std::ffi::OsString;
use std::path::Path;

use serde_json::{Value, json};

use super::configuration::{Configuration, RunConfiguration};
use super::contract::{Capabilities, Observation, encoded_size};
use super::corpus::{Corpus, CorpusStorage, HistoricalCorpus, load};
use super::model_originals::workflow::pipeline;
use super::report::{Failure, HistoricalReport, MAX_OBSERVATION_BYTES, Phase, Record, ResultKind};
use super::report_facade::{Report, ReportStorage};
use crate::transport::{Limits, Session};

pub struct RunOptions {
    pub adapter: OsString,
    pub adapter_args: Vec<OsString>,
    pub limits: Limits,
}

pub(super) trait Testee {
    fn exchange(&mut self, request: &Value) -> Result<Value, String>;
}

impl Testee for Session {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        let response = if request["contractVersion"] == super::contract::LOCAL_MODELS_VERSION
            || request["contractVersion"] == super::contract::ARTIFACT_TRANSFER_VERSION
            || request["contractVersion"] == super::contract::WORKSHEET_VERSION
            || request["contractVersion"] == super::contract::CODEC_COMPARISON_VERSION
            || request["contractVersion"] == super::contract::HTTP_POLICY_BOUNDARY_VERSION
            || request["contractVersion"] == super::contract::HTTP_POLICY_CLIENT_VERSION
            || request["contractVersion"] == super::contract::HTTP_POLICY_PROVIDER_VERSION
            || request["contractVersion"] == super::contract::NATIVE_POLICY_BOUNDARY_VERSION
            || request["contractVersion"] == super::contract::NATIVE_POLICY_CLIENT_VERSION
            || request["contractVersion"] == super::contract::NATIVE_POLICY_OWNER_VERSION
            || request["contractVersion"] == super::contract::EXECUTIONS_VERSION
            || request["contractVersion"] == super::contract::NATIVE_OWNER_VERSION
            || request["contractVersion"] == super::contract::CAPABILITY_EXECUTIONS_VERSION
            || request["contractVersion"] == super::contract::CAPABILITY_POLICY_VERSION
            || request["contractVersion"] == super::contract::SELECTED_SCHEME_VERSION
        {
            self.exchange_literal_exact(request)
        } else if request["contractVersion"] == super::contract::NATIVE_FRAMES_VERSION
            || request["contractVersion"] == super::contract::NATIVE_REPLIES_VERSION
            || request["contractVersion"] == super::contract::NATIVE_CLIENT_VERSION
        {
            self.exchange_literal(request)
        } else {
            self.exchange_serializable(request)
        };
        response.map(Value::Object).map_err(|e| e.to_string())
    }
}

pub fn run(root: &Path, options: &RunOptions) -> Result<Report, String> {
    run_configured(
        root,
        options,
        &RunConfiguration {
            mode: Configuration::Historical,
        },
    )
}
pub fn run_configured(
    root: &Path,
    options: &RunOptions,
    configuration: &RunConfiguration,
) -> Result<Report, String> {
    run_configured_with_session_factory(root, configuration, || match &configuration.mode {
        Configuration::Historical => {
            Session::spawn(&options.adapter, &options.adapter_args, options.limits)
        }
        Configuration::ModelOriginals(_) => {
            Session::spawn_mep(&options.adapter, &options.adapter_args, options.limits)
        }
        Configuration::NativeOriginals { .. }
        | Configuration::InstalledOriginals { .. }
        | Configuration::BrowserOriginals { .. } => {
            unreachable!("external dispatch rejects native configuration before factory")
        }
    })
}
/// The actual CLI uses this callback to install its existing terminator only
/// after source preparation. It receives no private core/context/expected data.
pub fn run_configured_with_session_factory<F>(
    root: &Path,
    configuration: &RunConfiguration,
    factory: F,
) -> Result<Report, String>
where
    F: FnOnce() -> Result<Session, crate::transport::TransportError>,
{
    if matches!(configuration.mode, Configuration::BrowserOriginals { .. }) {
        return Err("browser configuration requires a maintained browser adapter".into());
    }
    if matches!(
        configuration.mode,
        Configuration::NativeOriginals { .. } | Configuration::InstalledOriginals { .. }
    ) {
        return Err("native configuration requires explicit native adapter".into());
    }
    let corpus = load(root)?;
    dispatch(&corpus, configuration, factory)
}
fn dispatch<F>(
    corpus: &Corpus,
    configuration: &RunConfiguration,
    factory: F,
) -> Result<Report, String>
where
    F: FnOnce() -> Result<Session, crate::transport::TransportError>,
{
    match (&corpus.storage, &configuration.mode) {
        (CorpusStorage::Historical(corpus), Configuration::Historical) => match factory() {
            Ok(session) => Ok(run_historical_session(corpus, session)),
            Err(error) => Ok(Report::historical(HistoricalReport::adapter_error(
                corpus,
                error.to_string(),
            ))),
        },
        (CorpusStorage::ModelOriginals(source), Configuration::ModelOriginals(policy)) => {
            pipeline::execute(source, policy, factory).map(Report::selected)
        }
        (CorpusStorage::ModelOriginals(_), Configuration::Historical) => {
            Err(pipeline::MISSING_POLICY.into())
        }
        (CorpusStorage::Historical(_), Configuration::ModelOriginals(_)) => {
            Err("historical corpus requires historical checker policy".into())
        }
        (_, Configuration::BrowserOriginals { .. }) => {
            Err("browser configuration requires a maintained browser adapter".into())
        }
        (_, Configuration::NativeOriginals { .. } | Configuration::InstalledOriginals { .. }) => {
            Err("native configuration requires explicit native adapter".into())
        }
    }
}
/// Explicit pre1.0 source API successor: selected missing policy is an Err,
/// never a fabricated failure inventory. An already-created session is closed.
pub fn run_with_session(corpus: &Corpus, session: Session) -> Result<Report, String> {
    run_with_session_configured(
        corpus,
        session,
        &RunConfiguration {
            mode: Configuration::Historical,
        },
    )
}
pub fn run_with_session_configured(
    corpus: &Corpus,
    session: Session,
    configuration: &RunConfiguration,
) -> Result<Report, String> {
    let mismatch = match (&corpus.storage, &configuration.mode) {
        (_, Configuration::BrowserOriginals { .. }) => {
            Some("browser configuration requires a maintained browser adapter")
        }
        (_, Configuration::NativeOriginals { .. } | Configuration::InstalledOriginals { .. }) => {
            Some("native configuration requires explicit native adapter")
        }
        (CorpusStorage::ModelOriginals(_), Configuration::Historical) => {
            Some(pipeline::MISSING_POLICY)
        }
        (CorpusStorage::Historical(_), Configuration::ModelOriginals(_)) => {
            Some("historical corpus requires historical checker policy")
        }
        _ => None,
    };
    if let Some(primary) = mismatch {
        return match session.close() {
            Ok(()) => Err(primary.into()),
            Err(error) => Err(format!("{primary}; shutdown: {error}")),
        };
    }
    dispatch(corpus, configuration, || Ok(session))
}
fn run_historical_session(corpus: &HistoricalCorpus, mut session: Session) -> Report {
    let mut report = execute_historical(corpus, &mut session);
    if let Err(error) = session.close() {
        report
            .errors
            .push(Failure::new(Phase::Shutdown, error.to_string()));
    }
    report.finish();
    Report::historical(report)
}
pub fn check_report_configured(
    root: &Path,
    report: &Report,
    configuration: &RunConfiguration,
) -> Result<(), String> {
    match (&report.storage, &configuration.mode) {
        (_, Configuration::BrowserOriginals { .. }) => {
            Err("browser configuration has no report reader".into())
        }
        (ReportStorage::Historical(report), Configuration::Historical) => {
            super::report::check_historical_report(root, report)
        }
        (ReportStorage::ModelOriginals(report), Configuration::ModelOriginals(policy)) => {
            let corpus = load(root)?;
            match &corpus.storage {
                CorpusStorage::ModelOriginals(source) => pipeline::replay(source, policy, report),
                CorpusStorage::Historical(_) => Err("corpus/report family differs".into()),
            }
        }
        (ReportStorage::ModelOriginals(_), Configuration::Historical) => {
            Err(pipeline::MISSING_POLICY.into())
        }
        (ReportStorage::Historical(_), Configuration::ModelOriginals(_)) => {
            Err("historical report requires historical checker policy".into())
        }
        (ReportStorage::ModelOriginals(report), Configuration::NativeOriginals { checker, .. }) => {
            let corpus = load(root)?;
            match &corpus.storage {
                CorpusStorage::ModelOriginals(source) => {
                    pipeline::replay_native(source, checker, report)
                }
                CorpusStorage::Historical(_) => Err("corpus/report family differs".into()),
            }
        }
        (ReportStorage::Historical(_), Configuration::NativeOriginals { .. }) => {
            Err("historical report requires historical checker policy".into())
        }
        (
            ReportStorage::ModelOriginals(report),
            Configuration::InstalledOriginals {
                checker,
                consumer_observation,
                ..
            },
        ) => {
            let corpus = load(root)?;
            match &corpus.storage {
                CorpusStorage::ModelOriginals(source) => {
                    pipeline::replay_installed(source, checker, *consumer_observation, report)
                }
                CorpusStorage::Historical(_) => Err("corpus/report family differs".into()),
            }
        }
        (ReportStorage::Historical(_), Configuration::InstalledOriginals { .. }) => {
            Err("historical report requires historical checker policy".into())
        }
    }
}
pub fn run_configured_with_native_adapter(
    root: &Path,
    configuration: &RunConfiguration,
    adapter: &mut dyn super::model_originals::native::NativeOriginalAdapter,
) -> Result<Report, String> {
    let Configuration::NativeOriginals {
        checker,
        observation,
        private_record,
    } = &configuration.mode
    else {
        return Err("native adapter requires explicit native configuration".into());
    };
    let corpus = load(root)?;
    match &corpus.storage {
        CorpusStorage::ModelOriginals(source) => {
            pipeline::execute_native(source, checker, observation, private_record, adapter)
                .map(Report::selected)
        }
        CorpusStorage::Historical(_) => {
            Err("historical corpus requires historical checker policy".into())
        }
    }
}
pub fn run_configured_with_installed_client_adapter(
    root: &Path,
    configuration: &RunConfiguration,
    adapter: &mut dyn super::model_originals::installed::InstalledClientAdapter,
) -> Result<Report, String> {
    let Configuration::InstalledOriginals {
        checker,
        observation,
        private_record,
        installed_observation,
        consumer_observation,
    } = &configuration.mode
    else {
        return Err("installed adapter requires explicit installed configuration".into());
    };
    let corpus = load(root)?;
    match &corpus.storage {
        CorpusStorage::ModelOriginals(source) => pipeline::execute_installed(
            source,
            checker,
            observation,
            private_record,
            installed_observation,
            *consumer_observation,
            adapter,
        )
        .map(Report::selected),
        CorpusStorage::Historical(_) => {
            Err("historical corpus requires historical checker policy".into())
        }
    }
}
#[cfg(test)]
pub(super) fn execute(corpus: &Corpus, adapter: &mut dyn Testee) -> Report {
    let corpus = corpus
        .as_historical()
        .expect("historical Testee fixture selected a historical corpus");
    Report::historical(execute_historical(corpus, adapter))
}

fn execute_historical(corpus: &HistoricalCorpus, adapter: &mut dyn Testee) -> HistoricalReport {
    let mut report = HistoricalReport::new(corpus);
    let negotiated = adapter
        .exchange(
            &json!({"op":"capabilities","suite":"workbench","contractVersion":corpus.version}),
        )
        .and_then(|value| Capabilities::parse(value, &corpus.version));
    match negotiated {
        Ok(caps) => report.capabilities = Some(caps),
        Err(message) => report
            .errors
            .push(Failure::new(Phase::Capabilities, message)),
    }
    let mut broken = report.capabilities.is_none();
    let mut observation_budget = MAX_OBSERVATION_BYTES;
    for case in &corpus.cases {
        let mut record = Record {
            case_id: case.id.clone(),
            operation: case.operation,
            format: case.format,
            result: ResultKind::Error,
            observed: None,
        };
        if report
            .capabilities
            .as_ref()
            .is_some_and(|c| !c.supports(case.operation(), case.format))
        {
            record.result = ResultKind::Unsupported;
        } else if !broken {
            let observed = adapter
                .exchange(
                    &json!({"op":case.operation(),"suite":"workbench","contractVersion":corpus.version,
                "format":case.format,"input":case.input}),
                )
                .and_then(|value| {
                    if matches!(case.operation(), super::contract::Operation::InspectModel | super::contract::Operation::ExportModelOriginal) { super::local_models::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::ArtifactServer { super::artifacts::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::ArtifactClient { super::artifact_client::validate_observation_shape(&value)?; }
                    if matches!(case.operation(),super::contract::Operation::WorksheetEvaluate | super::contract::Operation::WorksheetValidate) {super::worksheet::validate_observation_shape(&value)?;}
                    if matches!(case.operation(), super::contract::Operation::TranscodeInvocations | super::contract::Operation::CompareValues) { super::codec_comparison::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::ValidateHttpPolicyBoundary { super::http_policy::Kit::Boundary.observation(&value)?; }
                    if case.operation() == super::contract::Operation::RunHttpPolicyClient { super::http_policy::Kit::Client.observation(&value)?; }
                    if case.operation() == super::contract::Operation::RunHttpPolicyProvider { super::http_policy::Kit::Provider.observation(&value)?; }
                    if case.operation() == super::contract::Operation::ReduceExecution {
                        super::executions::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::ValidateNativePolicyBoundary { super::native_policy_boundary::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::RunNativePolicyClient { super::native_policy_client::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::RunNativePolicyOwner { super::native_policy_owner::validate_observation_shape(&value)?; }
                    if case.operation() == super::contract::Operation::RunCapabilityExecutions {
                        super::capability_executions::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::RunCapabilityPolicy {
                        super::capability_policy::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::RunSelectedScheme {
                        super::selected_scheme::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::RunNativeOwner {
                        super::native_owner::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::RunNativeClient {
                        super::native_client::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::ValidateNativeReply {
                        super::native_replies::validate_observation_shape(&value)?;
                    }
                    if case.operation() == super::contract::Operation::ValidateNativeFrame {
                        super::native_frames::validate_observation_shape(&value)?;
                    }
                    Observation::parse(value)
                })
                .and_then(|observation| {
                    case.validate_observation(&observation)?;
                    let bytes = encoded_size(&observation, observation_budget)?;
                    observation_budget -= bytes;
                    case.expected
                        .matches(&observation, case.operation())
                        .map(|matches| (observation, matches))
                });
            match observed {
                Ok((observed, matches)) => {
                    record.result = if matches {
                        ResultKind::Pass
                    } else {
                        ResultKind::Fail
                    };
                    record.observed = Some(observed);
                }
                Err(message) => {
                    broken = true;
                    report.errors.push(Failure::new(Phase::Exchange, message));
                }
            }
        }
        report.records.push(record);
    }
    report.finish();
    report
}
