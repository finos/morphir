//! Commands for locating local troubleshooting data.

use serde::Serialize;
use starbase::AppResult;
use std::fs::File;
use std::io::{BufRead, BufReader, Read as _, Write as _};
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
            cli_logs: crate::home::effective_cli_logs_dir(&home),
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
    let key = key
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    [
        "token",
        "password",
        "secret",
        "authorization",
        "cookie",
        "apikey",
        "accesskey",
        "credential",
    ]
    .iter()
    .any(|needle| key.contains(needle))
}

fn contains_sensitive_assignment(value: &str) -> bool {
    value.match_indices('=').any(|(equals, _)| {
        let key = value[..equals]
            .trim_end()
            .chars()
            .rev()
            .take_while(|character| {
                character.is_ascii_alphanumeric() || matches!(character, '_' | '-')
            })
            .collect::<String>()
            .chars()
            .rev()
            .collect::<String>();
        !key.is_empty() && sensitive_key(&key)
    })
}

fn redact_urls(value: &str) -> String {
    let mut redacted = value.to_owned();
    let mut search_from = 0;

    while let Some(marker) = redacted[search_from..].find("://") {
        let authority_start = search_from + marker + 3;
        let token_end = redacted[authority_start..]
            .char_indices()
            .find(|(_, character)| {
                character.is_whitespace()
                    || matches!(
                        character,
                        ',' | ';' | '(' | ')' | '[' | ']' | '{' | '}' | '<' | '>'
                    )
            })
            .map(|(index, _)| authority_start + index)
            .unwrap_or(redacted.len());
        let authority_end = redacted[authority_start..token_end]
            .char_indices()
            .find(|(_, character)| matches!(character, '/' | '?' | '#'))
            .map(|(index, _)| authority_start + index)
            .unwrap_or(token_end);

        let scan_after =
            if let Some(user_info_end) = redacted[authority_start..authority_end].rfind('@') {
                let host_start = authority_start + user_info_end + 1;
                redacted.replace_range(authority_start..host_start, "[REDACTED]@");
                authority_start + "[REDACTED]@".len()
            } else {
                authority_start
            };

        let token_end = redacted[authority_start..]
            .char_indices()
            .find(|(_, character)| {
                character.is_whitespace()
                    || matches!(
                        character,
                        ',' | ';' | '(' | ')' | '[' | ']' | '{' | '}' | '<' | '>'
                    )
            })
            .map(|(index, _)| authority_start + index)
            .unwrap_or(redacted.len());
        if let Some(boundary) = redacted[authority_start..token_end]
            .char_indices()
            .find(|(_, character)| matches!(character, '?' | '#'))
            .map(|(index, _)| authority_start + index)
        {
            redacted.replace_range(boundary..token_end, "");
            search_from = boundary;
        } else {
            // Resume inside the current URL so every later scheme is inspected,
            // even when log formatting joins URLs with an unknown delimiter.
            search_from = scan_after;
        }
    }

    redacted
}

/// Sanitize free-form text before writing it to a correlated diagnostic event.
pub(crate) fn sanitize_text(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    if lower.contains("bearer ")
        || lower.contains("authorization: basic ")
        || lower.contains("authorization=basic ")
        || lower.contains("ghp_")
        || lower.contains("github_pat_")
        || lower.contains("password=")
        || lower.contains("token=")
        || lower.contains("secret=")
        || contains_sensitive_assignment(value)
    {
        return "[REDACTED]".to_owned();
    }
    if value.contains("://") {
        return redact_urls(value);
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
        serde_json::Value::String(value) => serde_json::Value::String(sanitize_text(&value)),
        value => value,
    }
}

fn normalize_paths(
    value: serde_json::Value,
    replacements: &[(&str, &'static str)],
) -> serde_json::Value {
    match value {
        serde_json::Value::Object(values) => serde_json::Value::Object(
            values
                .into_iter()
                .map(|(key, value)| (key, normalize_paths(value, replacements)))
                .collect(),
        ),
        serde_json::Value::Array(values) => serde_json::Value::Array(
            values
                .into_iter()
                .map(|value| normalize_paths(value, replacements))
                .collect(),
        ),
        serde_json::Value::String(value) => serde_json::Value::String(
            replacements
                .iter()
                .fold(value, |value, (path, label)| value.replace(path, label)),
        ),
        value => value,
    }
}

fn belongs_to_operation(event: &serde_json::Value, operation_id: &str) -> bool {
    let fields = &event["fields"];
    fields["operation_id"] == operation_id || fields["parent_operation_id"] == operation_id
}

fn operation_log_roots(home: &crate::home::MorphirHome) -> [PathBuf; 2] {
    [
        crate::home::effective_cli_logs_dir(home),
        home.desktop_logs_dir(),
    ]
}

fn for_each_bounded_line<R, F>(mut reader: R, max_len: usize, mut visit: F) -> std::io::Result<()>
where
    R: BufRead,
    F: FnMut(&[u8]),
{
    let read_limit = u64::try_from(max_len).unwrap_or(u64::MAX).saturating_add(2);
    loop {
        let mut line = Vec::with_capacity(max_len.min(8 * 1024));
        let read = reader
            .by_ref()
            .take(read_limit)
            .read_until(b'\n', &mut line)?;
        if read == 0 {
            return Ok(());
        }

        let terminated = line.last() == Some(&b'\n');
        if terminated {
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
        }
        if line.len() > max_len {
            if !terminated {
                reader.skip_until(b'\n')?;
            }
            continue;
        }

        visit(&line);
        if !terminated {
            return Ok(());
        }
    }
}

fn read_operation_events(log_roots: &[PathBuf], operation_id: &str) -> Vec<serde_json::Value> {
    let log_files = log_roots
        .iter()
        .flat_map(|root| WalkDir::new(root).follow_links(false).into_iter())
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .map(|entry| entry.into_path());
    let mut events = Vec::new();
    for path in log_files {
        if events.len() >= MAX_DIAGNOSTIC_EVENTS {
            break;
        }
        let Ok(file) = File::open(path) else {
            continue;
        };
        let _ = for_each_bounded_line(BufReader::new(file), 1024 * 1024, |line| {
            if events.len() >= MAX_DIAGNOSTIC_EVENTS {
                return;
            }
            if let Ok(event) = serde_json::from_slice::<serde_json::Value>(line)
                && belongs_to_operation(&event, operation_id)
            {
                events.push(sanitize(event));
            }
        });
    }
    events.sort_by(|left, right| left["timestamp"].as_str().cmp(&right["timestamp"].as_str()));
    events
}

/// Show sanitized CLI and Desktop events for one reported operation ID.
pub fn run_diagnostics_show(operation: &str, json: bool) -> AppResult<miette::Report> {
    let operation_id = crate::observability::OperationId::parse(operation)
        .ok_or_else(|| miette::miette!("Invalid Morphir operation ID: {operation}"))?;
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let log_roots = operation_log_roots(&home);
    let result = OperationEvents {
        operation_id: operation_id.to_string(),
        events: read_operation_events(&log_roots, operation_id.as_str()),
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

fn bundle_events(
    events: Vec<serde_json::Value>,
    home: &Path,
    log_roots: &[PathBuf],
) -> miette::Result<Vec<u8>> {
    let home = home.to_string_lossy().into_owned();
    let external_log_roots = log_roots
        .iter()
        .filter(|root| !root.starts_with(home.as_str()))
        .map(|root| root.to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    let mut replacements = vec![(home.as_str(), "$MORPHIR_HOME")];
    replacements.extend(
        external_log_roots
            .iter()
            .map(|root| (root.as_str(), "$MORPHIR_LOG_DIR")),
    );
    let mut bytes = Vec::new();
    for event in events {
        serde_json::to_writer(&mut bytes, &normalize_paths(event, &replacements))
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
    let log_roots = operation_log_roots(&home);
    let events = bundle_events(
        read_operation_events(&log_roots, operation_id.as_str()),
        home.root(),
        &log_roots,
    )?;
    let system = serde_json::to_vec_pretty(&BundleSystem {
        schema_version: 1,
        cli_version: env!("CARGO_PKG_VERSION"),
        operating_system: std::env::consts::OS,
        architecture: std::env::consts::ARCH,
        morphir_home: "$MORPHIR_HOME",
        home_exists: home.root().is_dir(),
        logs_exist: log_roots.iter().any(|path| path.is_dir()),
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

#[cfg(test)]
mod tests {
    use super::{for_each_bounded_line, sanitize_text};
    use std::io::{BufReader, Cursor};

    #[test]
    fn bounded_reader_discards_an_oversized_record_and_resumes() {
        let mut input = vec![b'x'; 64];
        input.extend_from_slice(b"\nkept\r\n");
        let reader = BufReader::with_capacity(8, Cursor::new(input));
        let mut lines = Vec::new();

        for_each_bounded_line(reader, 16, |line| lines.push(line.to_vec())).unwrap();

        assert_eq!(lines, [b"kept".as_slice()]);
    }

    #[test]
    fn free_form_sensitive_assignments_are_redacted() {
        for value in [
            "api_key=LIVE_SECRET",
            "apiKey=LIVE_SECRET",
            "access-key=LIVE_SECRET",
            "credential=LIVE_SECRET",
        ] {
            assert_eq!(sanitize_text(value), "[REDACTED]");
        }
    }

    #[test]
    fn every_url_in_free_form_text_is_sanitized() {
        assert_eq!(
            sanitize_text(
                "https://public.example/status|https://alice:hunter2@private.example/artifact"
            ),
            "https://public.example/status|https://[REDACTED]@private.example/artifact"
        );
    }
}
