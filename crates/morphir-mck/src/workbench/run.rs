use std::ffi::OsString;
use std::path::Path;

use serde_json::{Value, json};

use super::contract::{Capabilities, Observation, encoded_size};
use super::corpus::{Corpus, load};
use super::report::{Failure, MAX_OBSERVATION_BYTES, Phase, Record, Report, ResultKind};
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
        let response = if request["contractVersion"] == super::contract::ARTIFACT_TRANSFER_VERSION
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
    let corpus = load(root)?;
    match Session::spawn(&options.adapter, &options.adapter_args, options.limits) {
        Err(error) => Ok(Report::adapter_error(&corpus, error.to_string())),
        Ok(session) => Ok(run_with_session(&corpus, session)),
    }
}

/// Consume a shared bounded session after the command layer installs its Ctrl-C
/// terminator. Adapter shutdown remains part of compatibility qualification.
pub fn run_with_session(corpus: &Corpus, mut session: Session) -> Report {
    let mut report = execute(corpus, &mut session);
    if let Err(error) = session.close() {
        report
            .errors
            .push(Failure::new(Phase::Shutdown, error.to_string()));
    }
    report.finish();
    report
}

pub(super) fn execute(corpus: &Corpus, adapter: &mut dyn Testee) -> Report {
    let mut report = Report::new(corpus);
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
