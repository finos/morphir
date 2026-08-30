//! Commands for locating local troubleshooting data.

use serde::Serialize;
use starbase::AppResult;
use std::fs::File;
use std::io::{BufRead, BufReader, Write as _};
use std::path::{Path, PathBuf};
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

fn normalize_home(value: serde_json::Value, home: &str) -> serde_json::Value {
    match value {
        serde_json::Value::Object(values) => serde_json::Value::Object(
            values
                .into_iter()
                .map(|(key, value)| (key, normalize_home(value, home)))
                .collect(),
        ),
        serde_json::Value::Array(values) => serde_json::Value::Array(
            values
                .into_iter()
                .map(|value| normalize_home(value, home))
                .collect(),
        ),
        serde_json::Value::String(value) => {
            serde_json::Value::String(value.replace(home, "$MORPHIR_HOME"))
        }
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

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BundleSystem {
    schema_version: u8,
    cli_version: &'static str,
    operating_system: &'static str,
    architecture: &'static str,
    morphir_home: &'static str,
    home_exists: bool,
    logs_exist: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct IncludedFile {
    path: &'static str,
    bytes: usize,
    sha256: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ExcludedContent {
    content: &'static str,
    reason: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BundleManifest {
    schema_version: u8,
    operation_id: String,
    included_files: Vec<IncludedFile>,
    exclusions: Vec<ExcludedContent>,
}

fn included(path: &'static str, bytes: &[u8]) -> IncludedFile {
    IncludedFile {
        path,
        bytes: bytes.len(),
        sha256: morphir_distribution::Sha256Digest::of_bytes(bytes).to_string(),
    }
}

fn bundle_events(events: Vec<serde_json::Value>, home: &Path) -> miette::Result<Vec<u8>> {
    let home = home.to_string_lossy();
    let mut bytes = Vec::new();
    for event in events {
        serde_json::to_writer(&mut bytes, &normalize_home(event, &home))
            .map_err(|error| miette::miette!("Failed to serialize diagnostic event: {error}"))?;
        bytes.push(b'\n');
    }
    Ok(bytes)
}

fn write_bundle_entry<W: std::io::Write + std::io::Seek>(
    archive: &mut zip::ZipWriter<W>,
    path: &str,
    bytes: &[u8],
) -> miette::Result<()> {
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o600);
    archive
        .start_file(path, options)
        .map_err(|error| miette::miette!("Failed to add {path} to diagnostic bundle: {error}"))?;
    archive
        .write_all(bytes)
        .map_err(|error| miette::miette!("Failed to write {path} to diagnostic bundle: {error}"))
}

/// Create a local, sanitized ZIP without replacing an existing file.
pub fn run_diagnostics_collect(operation: &str, output: &Path) -> AppResult<miette::Report> {
    let operation_id = crate::observability::OperationId::parse(operation)
        .ok_or_else(|| miette::miette!("Invalid Morphir operation ID: {operation}"))?;
    if output.exists() {
        return Err(miette::miette!(
            "Diagnostic bundle already exists: {}",
            output.display()
        ));
    }
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let events = bundle_events(
        read_operation_events(&home.logs_dir(), operation_id.as_str()),
        home.root(),
    )?;
    let system = serde_json::to_vec_pretty(&BundleSystem {
        schema_version: 1,
        cli_version: env!("CARGO_PKG_VERSION"),
        operating_system: std::env::consts::OS,
        architecture: std::env::consts::ARCH,
        morphir_home: "$MORPHIR_HOME",
        home_exists: home.root().is_dir(),
        logs_exist: home.logs_dir().is_dir(),
    })
    .map_err(|error| miette::miette!("Failed to serialize bundle system summary: {error}"))?;
    let manifest = BundleManifest {
        schema_version: 1,
        operation_id: operation_id.to_string(),
        included_files: vec![
            included("events.jsonl", &events),
            included("system.json", &system),
        ],
        exclusions: vec![
            ExcludedContent {
                content: "project sources, Morphir IR, and generated output",
                reason: "never collected by default",
            },
            ExcludedContent {
                content: "configuration, environment variables, credentials, and secret stores",
                reason: "sensitive inputs are excluded",
            },
            ExcludedContent {
                content: "crash dumps",
                reason: "no authenticated operation association is available yet",
            },
            ExcludedContent {
                content: "tool catalog and acquisition policy",
                reason: "sanitized integrity summary is not implemented yet",
            },
        ],
    };
    let manifest = serde_json::to_vec_pretty(&manifest)
        .map_err(|error| miette::miette!("Failed to serialize bundle manifest: {error}"))?;

    let parent = output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).map_err(|error| {
        miette::miette!(
            "Failed to create diagnostic bundle directory {}: {error}",
            parent.display()
        )
    })?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".morphir-diagnostics-")
        .suffix(".tmp")
        .tempfile_in(parent)
        .map_err(|error| miette::miette!("Failed to stage diagnostic bundle: {error}"))?;
    {
        let mut archive = zip::ZipWriter::new(temporary.as_file_mut());
        write_bundle_entry(&mut archive, "events.jsonl", &events)?;
        write_bundle_entry(&mut archive, "system.json", &system)?;
        write_bundle_entry(&mut archive, "manifest.json", &manifest)?;
        archive
            .finish()
            .map_err(|error| miette::miette!("Failed to finish diagnostic bundle: {error}"))?;
    }
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| miette::miette!("Failed to flush diagnostic bundle: {error}"))?;
    temporary.persist_noclobber(output).map_err(|error| {
        miette::miette!(
            "Failed to publish diagnostic bundle {}: {}",
            output.display(),
            error.error
        )
    })?;
    println!("Created diagnostic bundle: {}", output.display());
    Ok(None)
}
