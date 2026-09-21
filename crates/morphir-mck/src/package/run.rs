use super::{Capabilities, Kit, Record, Report, ResultKind};
use crate::transport::{Limits, Session};
use serde_json::Value;
use std::ffi::{OsStr, OsString};

/// Execute only a valid kit. Spawn failures remain report records.
pub fn run_process(
    kit: &Kit,
    program: &OsStr,
    args: &[OsString],
    limits: Limits,
    driver_version: &str,
    started_at: &str,
) -> Report {
    if !kit.errors.is_empty() || kit.cases.is_empty() {
        return Report::kit_error(kit, driver_version, started_at);
    }
    match Session::spawn(&program.to_os_string(), args, limits) {
        Ok(session) => run_kit(kit, session, driver_version, started_at),
        Err(error) => Report::adapter_error(kit, driver_version, started_at, error.to_string()),
    }
}
/// Consumes the session; adapter shutdown is part of the report.
pub fn run_kit(kit: &Kit, mut session: Session, driver_version: &str, started_at: &str) -> Report {
    let mut report = if !kit.errors.is_empty() || kit.cases.is_empty() {
        Report::kit_error(kit, driver_version, started_at)
    } else {
        execute(kit, &mut session, driver_version, started_at)
    };
    if let Err(error) = session.close() {
        report.error("package-adapter-close", error.to_string());
    }
    report
}
fn execute(kit: &Kit, session: &mut Session, driver_version: &str, started_at: &str) -> Report {
    let capabilities = session
        .exchange_serializable(&crate::transport::protocol::Request::Capabilities)
        .map_err(|error| error.to_string())
        .and_then(|body| Capabilities::parse(&Value::Object(body), kit.contract));
    let capabilities = match capabilities {
        Ok(caps) => caps,
        Err(error) => return Report::adapter_error(kit, driver_version, started_at, error),
    };
    let mut report = Report::new(kit, driver_version, started_at);
    for case in &kit.cases {
        let operation = case.request.operation();
        let mut record = Record {
            case_id: case.id.clone(),
            operation: Some(operation),
            result: ResultKind::Pass,
            message: None,
        };
        if !capabilities.supports(operation) {
            record.result = ResultKind::Skipped;
            record.message = Some("required operation unsupported".into());
            report.records.push(record);
            continue;
        }
        let compared = session
            .exchange_serializable(&case.request)
            .map_err(|error| error.to_string())
            .and_then(|body| {
                let actual = kit.project_response(operation, &Value::Object(body))?;
                let expected = kit.project_response(operation, case.expected())?;
                Ok((expected, actual))
            });
        match compared {
            Ok((expected, actual)) if expected != actual => {
                record.result = ResultKind::Fail;
                record.message = Some(format!("expected {expected}, got {actual}"));
            }
            Ok(_) => {}
            Err(error) => {
                record.result = ResultKind::KitError;
                record.message = Some(error);
            }
        }
        let stop = record.result == ResultKind::KitError;
        report.records.push(record);
        if stop {
            break;
        }
    }
    report.testee = Some(capabilities);
    report
}
