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
        self.exchange_serializable(request)
            .map(Value::Object)
            .map_err(|e| e.to_string())
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
                .and_then(Observation::parse)
                .and_then(|observation| {
                    observation.validate_for(case.operation())?;
                    let bytes = encoded_size(&observation, observation_budget)?;
                    observation_budget -= bytes;
                    case.expected
                        .matches(&observation)
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
