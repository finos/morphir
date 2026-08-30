//! Commands for locating local troubleshooting data.

use serde::Serialize;
use starbase::AppResult;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use walkdir::WalkDir;

const MAX_DIAGNOSTIC_EVENTS: usize = 10_000;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DiagnosticPaths {
    morphir_home: PathBuf,
    logs: PathBuf,
    cli_logs: PathBuf,
    desktop_logs: PathBuf,
}

impl DiagnosticPaths {
    fn resolve() -> miette::Result<Self> {
        let home = crate::home::MorphirHome::resolve()
            .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;

        Ok(Self {
            morphir_home: home.root().to_path_buf(),
            logs: home.logs_dir(),
            cli_logs: home.cli_logs_dir(),
            desktop_logs: home.desktop_logs_dir(),
        })
    }
}

/// Print the stable locations for Morphir's local logs.
pub fn run_diagnostics_path(json: bool) -> AppResult<miette::Report> {
    let paths = DiagnosticPaths::resolve()?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&paths)
                .map_err(|error| miette::miette!("Failed to serialize log paths: {error}"))?
        );
    } else {
        println!("Morphir Home: {}", paths.morphir_home.display());
        println!("Logs: {}", paths.logs.display());
        println!("CLI logs: {}", paths.cli_logs.display());
        println!("Desktop logs: {}", paths.desktop_logs.display());
    }

    Ok(None)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationEvents {
    operation_id: String,
    events: Vec<serde_json::Value>,
}

fn sensitive_key(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    ["token", "password", "secret", "authorization", "cookie"]
        .iter()
        .any(|needle| key.contains(needle))
}

fn redact_text(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    if lower.contains("bearer ")
        || lower.contains("ghp_")
        || lower.contains("github_pat_")
        || lower.contains("password=")
        || lower.contains("token=")
        || lower.contains("secret=")
    {
        return "[REDACTED]".to_owned();
    }
    if value.contains("://") {
        let boundary = value
            .char_indices()
            .filter(|(_, character)| matches!(character, '?' | '#'))
            .map(|(index, _)| index)
            .min();
        if let Some(boundary) = boundary {
            return value[..boundary].to_owned();
        }
    }
    value.to_owned()
}

fn sanitize(value: serde_json::Value) -> serde_json::Value {
    match value {
        serde_json::Value::Object(values) => serde_json::Value::Object(
            values
                .into_iter()
                .map(|(key, value)| {
                    let value = if sensitive_key(&key) {
                        serde_json::Value::String("[REDACTED]".to_owned())
                    } else {
                        sanitize(value)
                    };
                    (key, value)
                })
                .collect(),
        ),
        serde_json::Value::Array(values) => {
            serde_json::Value::Array(values.into_iter().map(sanitize).collect())
        }
        serde_json::Value::String(value) => serde_json::Value::String(redact_text(&value)),
        value => value,
    }
}

fn belongs_to_operation(event: &serde_json::Value, operation_id: &str) -> bool {
    let fields = &event["fields"];
    fields["operation_id"] == operation_id || fields["parent_operation_id"] == operation_id
}

fn read_operation_events(logs: &std::path::Path, operation_id: &str) -> Vec<serde_json::Value> {
    let mut events = [logs.join("cli"), logs.join("desktop")]
        .into_iter()
        .flat_map(|root| WalkDir::new(root).follow_links(false).into_iter())
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .filter_map(|entry| File::open(entry.path()).ok())
        .flat_map(|file| BufReader::new(file).lines().map_while(Result::ok))
        .filter(|line| line.len() <= 1024 * 1024)
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(&line).ok())
        .filter(|event| belongs_to_operation(event, operation_id))
        .map(sanitize)
        .take(MAX_DIAGNOSTIC_EVENTS)
        .collect::<Vec<_>>();
    events.sort_by(|left, right| left["timestamp"].as_str().cmp(&right["timestamp"].as_str()));
    events
}

/// Show sanitized CLI and Desktop events for one reported operation ID.
pub fn run_diagnostics_show(operation: &str, json: bool) -> AppResult<miette::Report> {
    let operation_id = crate::observability::OperationId::parse(operation)
        .ok_or_else(|| miette::miette!("Invalid Morphir operation ID: {operation}"))?;
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let result = OperationEvents {
        operation_id: operation_id.to_string(),
        events: read_operation_events(&home.logs_dir(), operation_id.as_str()),
    };

    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&result).map_err(|error| miette::miette!(
                "Failed to serialize diagnostic events: {error}"
            ))?
        );
    } else if result.events.is_empty() {
        println!("No local events found for {operation_id}");
    } else {
        for event in &result.events {
            let timestamp = event["timestamp"].as_str().unwrap_or("unknown-time");
            let level = event["level"].as_str().unwrap_or("UNKNOWN");
            let name = event["fields"]["event_name"]
                .as_str()
                .unwrap_or("unknown-event");
            println!("{timestamp} {level} {name}");
        }
    }
    Ok(None)
}
