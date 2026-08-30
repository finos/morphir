//! Commands for locating local troubleshooting data.

use serde::Serialize;
use starbase::AppResult;
use std::cmp::{Ordering, Reverse};
use std::collections::{BTreeSet, BinaryHeap};
use std::fs::File;
use std::io::{BufRead, BufReader, Read as _, Seek as _, SeekFrom, Write as _};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

const MAX_DIAGNOSTIC_EVENTS: usize = 10_000;
const MAX_DIAGNOSTIC_EVENT_BYTES: usize = 16 * 1024 * 1024;
const MAX_DIAGNOSTIC_SCAN_BYTES: usize = 64 * 1024 * 1024;

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
    truncated: bool,
    events: Vec<serde_json::Value>,
}

struct DiagnosticEvents {
    events: Vec<serde_json::Value>,
    truncated: bool,
}

struct RetainedEvent {
    order: (Option<String>, usize),
    bytes: usize,
    value: serde_json::Value,
}

impl PartialEq for RetainedEvent {
    fn eq(&self, other: &Self) -> bool {
        self.order == other.order
    }
}

impl Eq for RetainedEvent {}

impl PartialOrd for RetainedEvent {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for RetainedEvent {
    fn cmp(&self, other: &Self) -> Ordering {
        self.order.cmp(&other.order)
    }
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
        "passwd",
        "secret",
        "authorization",
        "cookie",
        "apikey",
        "accesskey",
        "credential",
        "privatekey",
        "passphrase",
    ]
    .iter()
    .any(|needle| key.contains(needle))
}

fn contains_sensitive_assignment(value: &str) -> bool {
    value
        .char_indices()
        .filter(|(_, character)| matches!(character, '=' | ':'))
        .any(|(separator, _)| {
            let key = value[..separator]
                .trim_end()
                .trim_end_matches(['\'', '"', '\\', ']', ')', '}'])
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

fn contains_authorization_header(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.match_indices("authorization").any(|(start, _)| {
        let rest = lower[start + "authorization".len()..].trim_start();
        let Some(rest) = rest.strip_prefix(':').or_else(|| rest.strip_prefix('=')) else {
            return false;
        };
        let scheme = rest.trim_start();
        ["basic", "bearer"].iter().any(|candidate| {
            scheme.strip_prefix(candidate).is_some_and(|remainder| {
                remainder.is_empty() || remainder.chars().next().is_some_and(char::is_whitespace)
            })
        })
    })
}

fn contains_sensitive_option_pair(value: &str) -> bool {
    let tokens = value.split_whitespace().collect::<Vec<_>>();
    tokens.windows(2).any(|pair| {
        let value = pair[1].trim_matches(|character| {
            matches!(
                character,
                '\'' | '"' | '[' | ']' | '(' | ')' | '{' | '}' | ','
            )
        });
        sensitive_long_option(pair[0]) && !value.is_empty() && !value.starts_with("--")
    })
}

fn sensitive_long_option(value: &str) -> bool {
    value
        .trim_matches(|character| {
            matches!(
                character,
                '\'' | '"' | '[' | ']' | '(' | ')' | '{' | '}' | ','
            )
        })
        .strip_prefix("--")
        .is_some_and(sensitive_key)
}

fn sensitive_long_option_consumes_next(value: &str) -> bool {
    let option = value.trim_matches(|character| {
        matches!(
            character,
            '\'' | '"' | '[' | ']' | '(' | ')' | '{' | '}' | ','
        )
    });
    sensitive_long_option(option) && !option.contains('=')
}

fn url_scheme_start_before(value: &str, marker: usize) -> Option<usize> {
    let start = value[..marker]
        .char_indices()
        .rev()
        .find(|(_, character)| {
            !(character.is_ascii_alphanumeric() || matches!(character, '+' | '-' | '.'))
        })
        .map(|(index, character)| index + character.len_utf8())
        .unwrap_or(0);
    let scheme = &value[start..marker];
    scheme
        .chars()
        .next()
        .is_some_and(|first| first.is_ascii_alphabetic())
        .then_some(start)
}

fn url_token_end(value: &str, authority_start: usize) -> usize {
    let delimiter = value[authority_start..]
        .char_indices()
        .find(|(_, character)| {
            character.is_whitespace() || matches!(character, '\'' | '"' | '<' | '>')
        })
        .map(|(index, _)| authority_start + index)
        .unwrap_or(value.len());
    value[authority_start..delimiter]
        .match_indices("://")
        .find_map(|(index, _)| {
            let start = url_scheme_start_before(value, authority_start + index)?;
            (start >= authority_start && url_separator_before(value, start).is_some())
                .then_some(start)
        })
        .unwrap_or(delimiter)
}

fn url_separator_before(value: &str, start: usize) -> Option<usize> {
    value[..start]
        .char_indices()
        .next_back()
        .filter(|(_, character)| matches!(character, '|' | ',' | ';'))
        .map(|(index, _)| index)
}

fn url_scheme_starts_at(value: &str, start: usize) -> bool {
    value[start..]
        .find("://")
        .is_some_and(|marker| url_scheme_start_before(value, start + marker) == Some(start))
}

fn redact_urls(value: &str) -> String {
    let mut redacted = value.to_owned();
    let mut search_from = 0;

    while let Some(marker) = redacted[search_from..].find("://") {
        let authority_start = search_from + marker + 3;
        let token_end = url_token_end(&redacted, authority_start);
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

        let token_end = url_token_end(&redacted, authority_start);
        if let Some(boundary) = redacted[authority_start..token_end]
            .char_indices()
            .find(|(_, character)| matches!(character, '?' | '#'))
            .map(|(index, _)| authority_start + index)
        {
            let replacement_end = url_scheme_starts_at(&redacted, token_end)
                .then(|| url_separator_before(&redacted, token_end))
                .flatten()
                .unwrap_or(token_end);
            redacted.replace_range(boundary..replacement_end, "");
            search_from = boundary;
        } else {
            // Resume inside the current URL so every later scheme is inspected,
            // even when log formatting joins URLs with an unknown delimiter.
            search_from = scan_after;
        }
    }

    redacted
}

fn reference_token_end(value: &str, authority_start: usize) -> usize {
    value[authority_start..]
        .char_indices()
        .find(|(_, character)| {
            character.is_whitespace() || matches!(character, '\'' | '"' | '<' | '>' | '|')
        })
        .map(|(index, _)| authority_start + index)
        .unwrap_or(value.len())
}

fn redact_scheme_relative_urls(value: &str) -> String {
    let mut redacted = value.to_owned();
    let mut search_from = 0;

    while let Some(relative_start) = redacted[search_from..].find("//") {
        let start = search_from + relative_start;
        let preceded_by_colon = redacted[..start].ends_with(':');
        if preceded_by_colon || !path_boundary_before(&redacted, start) {
            search_from = start + 2;
            continue;
        }

        let authority_start = start + 2;
        let token_end = reference_token_end(&redacted, authority_start);
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

        let token_end = reference_token_end(&redacted, authority_start);
        if let Some(boundary) = redacted[authority_start..token_end]
            .char_indices()
            .find(|(_, character)| matches!(character, '?' | '#'))
            .map(|(index, _)| authority_start + index)
        {
            redacted.replace_range(boundary..token_end, "");
            search_from = boundary;
        } else {
            search_from = scan_after;
        }
    }

    redacted
}

/// Sanitize free-form text before writing it to a correlated diagnostic event.
pub(crate) fn sanitize_text(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    if lower.contains("bearer ")
        || contains_authorization_header(value)
        || lower.contains("ghp_")
        || lower.contains("github_pat_")
        || (lower.contains("-----begin ") && lower.contains("private key-----"))
        || lower.contains("password=")
        || lower.contains("token=")
        || lower.contains("secret=")
        || contains_sensitive_assignment(value)
        || contains_sensitive_option_pair(value)
    {
        return "[REDACTED]".to_owned();
    }
    let value = if value.contains("://") {
        redact_urls(value)
    } else {
        value.to_owned()
    };
    if value.contains("//") {
        redact_scheme_relative_urls(&value)
    } else {
        value
    }
}

fn path_boundary_before(value: &str, start: usize) -> bool {
    start == 0
        || value[..start].chars().next_back().is_some_and(|character| {
            !character.is_ascii_alphanumeric() && !matches!(character, '$' | '_')
        })
}

fn absolute_path_start(value: &str, start: usize) -> bool {
    let bytes = value.as_bytes();
    let posix = bytes[start] == b'/'
        && bytes.get(start + 1) != Some(&b'/')
        && !(start > 0 && bytes[start - 1] == b':')
        && !(start > 1 && bytes[start - 1] == b'/' && bytes[start - 2] == b':')
        && path_boundary_before(value, start);
    let windows_drive = bytes[start].is_ascii_alphabetic()
        && bytes.get(start + 1) == Some(&b':')
        && bytes
            .get(start + 2)
            .is_some_and(|separator| matches!(separator, b'/' | b'\\'))
        && path_boundary_before(value, start);
    let windows_unc = bytes[start] == b'\\'
        && bytes.get(start + 1) == Some(&b'\\')
        && path_boundary_before(value, start);
    posix || windows_drive || windows_unc
}

fn redact_unknown_absolute_paths(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut cursor = 0;

    while let Some(start) = (cursor..value.len())
        .filter(|index| value.is_char_boundary(*index))
        .find(|index| absolute_path_start(value, *index))
    {
        result.push_str(&value[cursor..start]);
        let closing_delimiter =
            value[..start]
                .chars()
                .next_back()
                .and_then(|character| match character {
                    '\'' => Some('\''),
                    '"' => Some('"'),
                    '(' => Some(')'),
                    '[' => Some(']'),
                    '{' => Some('}'),
                    '<' => Some('>'),
                    _ => None,
                });
        let end = value[start..]
            .char_indices()
            .skip(1)
            .find(|(offset, character)| {
                matches!(character, '\r' | '\n')
                    || Some(*character) == closing_delimiter
                    || (*character == ':'
                        && value[start + offset + character.len_utf8()..]
                            .chars()
                            .next()
                            .is_some_and(char::is_whitespace))
            })
            .map(|(offset, _)| start + offset)
            .unwrap_or(value.len());
        result.push_str("$ABSOLUTE_PATH");
        cursor = end;
    }

    result.push_str(&value[cursor..]);
    result
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
        serde_json::Value::Array(values) => serde_json::Value::Array(sanitize_array(values)),
        serde_json::Value::String(value) => serde_json::Value::String(sanitize_text(&value)),
        value => value,
    }
}

fn sanitize_array(values: Vec<serde_json::Value>) -> Vec<serde_json::Value> {
    if let [serde_json::Value::String(key), _] = values.as_slice()
        && sensitive_key(key)
    {
        return vec![
            serde_json::Value::String(key.clone()),
            serde_json::Value::String("[REDACTED]".to_owned()),
        ];
    }
    let mut redact_next = false;
    values
        .into_iter()
        .map(|value| {
            let long_option = value
                .as_str()
                .is_some_and(|value| value.trim_matches(['\'', '"']).starts_with("--"));
            if redact_next && !long_option {
                redact_next = false;
                return serde_json::Value::String("[REDACTED]".to_owned());
            }
            redact_next = value
                .as_str()
                .is_some_and(sensitive_long_option_consumes_next);
            sanitize(value)
        })
        .collect()
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
        serde_json::Value::String(value) => {
            let normalized = replacements.iter().fold(value, |value, (path, label)| {
                replace_known_path(&value, path, label)
            });
            serde_json::Value::String(redact_unknown_absolute_paths(&normalized))
        }
        value => value,
    }
}

fn replace_known_path(value: &str, path: &str, label: &str) -> String {
    if path.is_empty() {
        return value.to_owned();
    }
    let mut result = String::with_capacity(value.len());
    let mut copied_through = 0;
    let mut search_from = 0;

    while let Some(relative_start) = value[search_from..].find(path) {
        let start = search_from + relative_start;
        let end = start + path.len();
        let boundary_after = end == value.len()
            || value[end..]
                .chars()
                .next()
                .is_some_and(|character| matches!(character, '/' | '\\'));
        if path_boundary_before(value, start) && boundary_after {
            result.push_str(&value[copied_through..start]);
            result.push_str(label);
            copied_through = end;
        }
        search_from = end;
    }

    result.push_str(&value[copied_through..]);
    result
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
    F: FnMut(&[u8]) -> bool,
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

        if !visit(&line) {
            return Ok(());
        }
        if !terminated {
            return Ok(());
        }
    }
}

fn read_operation_events(log_roots: &[PathBuf], operation_id: &str) -> DiagnosticEvents {
    read_operation_events_with_limits(
        log_roots,
        operation_id,
        MAX_DIAGNOSTIC_EVENTS,
        MAX_DIAGNOSTIC_EVENT_BYTES,
        MAX_DIAGNOSTIC_SCAN_BYTES,
    )
}

fn read_operation_events_with_limits(
    log_roots: &[PathBuf],
    operation_id: &str,
    max_events: usize,
    max_bytes: usize,
    max_scan_bytes: usize,
) -> DiagnosticEvents {
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
        .map(|entry| {
            let path = entry.into_path();
            path.canonicalize().unwrap_or(path)
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let mut log_files = log_files;
    log_files.sort_by(|left, right| {
        let modified = |path: &Path| path.metadata().and_then(|value| value.modified()).ok();
        modified(right)
            .cmp(&modified(left))
            .then_with(|| right.cmp(left))
    });
    let mut events = BinaryHeap::new();
    let mut retained_bytes = 0usize;
    let mut matched_events = 0usize;
    let mut truncated = false;
    let mut remaining_scan_bytes = max_scan_bytes;
    for path in log_files {
        if remaining_scan_bytes == 0 {
            truncated = true;
            break;
        }
        let Ok(mut file) = File::open(path) else {
            continue;
        };
        let Ok(file_bytes) = file.metadata().map(|metadata| metadata.len()) else {
            continue;
        };
        let scan_bytes = file_bytes.min(remaining_scan_bytes as u64);
        let start = file_bytes.saturating_sub(scan_bytes);
        if start > 0 {
            truncated = true;
            if file.seek(SeekFrom::Start(start)).is_err() {
                continue;
            }
        }
        remaining_scan_bytes = remaining_scan_bytes.saturating_sub(scan_bytes as usize);
        let mut reader = BufReader::new(file);
        if start > 0 && reader.skip_until(b'\n').is_err() {
            continue;
        }
        let _ = for_each_bounded_line(reader, 1024 * 1024, |line| {
            if let Ok(event) = serde_json::from_slice::<serde_json::Value>(line)
                && belongs_to_operation(&event, operation_id)
            {
                let order = (
                    event["timestamp"].as_str().map(ToOwned::to_owned),
                    matched_events,
                );
                matched_events = matched_events.saturating_add(1);
                retained_bytes = retained_bytes.saturating_add(line.len());
                events.push(Reverse(RetainedEvent {
                    order,
                    bytes: line.len(),
                    value: sanitize(event),
                }));
                while events.len() > max_events || retained_bytes > max_bytes {
                    let Some(Reverse(removed)) = events.pop() else {
                        break;
                    };
                    retained_bytes = retained_bytes.saturating_sub(removed.bytes);
                    truncated = true;
                }
            }
            true
        });
    }
    let mut events = events
        .into_iter()
        .map(|Reverse(event)| event)
        .collect::<Vec<_>>();
    events.sort_by(|left, right| left.order.cmp(&right.order));
    DiagnosticEvents {
        events: events.into_iter().map(|event| event.value).collect(),
        truncated,
    }
}

/// Show sanitized CLI and Desktop events for one reported operation ID.
pub fn run_diagnostics_show(operation: &str, json: bool) -> AppResult<miette::Report> {
    let operation_id = crate::observability::OperationId::parse(operation)
        .ok_or_else(|| miette::miette!("Invalid Morphir operation ID: {operation}"))?;
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;
    let log_roots = operation_log_roots(&home);
    let selected = read_operation_events(&log_roots, operation_id.as_str());
    let result = OperationEvents {
        operation_id: operation_id.to_string(),
        truncated: selected.truncated,
        events: selected.events,
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
        if result.truncated {
            println!("Older diagnostic events were omitted because the display limit was reached.");
        }
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
    diagnostic_events_truncated: bool,
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
    let selected = read_operation_events(&log_roots, operation_id.as_str());
    let events = bundle_events(selected.events, home.root(), &log_roots)?;
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
        diagnostic_events_truncated: selected.truncated,
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
    use super::{
        for_each_bounded_line, normalize_paths, read_operation_events_with_limits, sanitize,
        sanitize_text,
    };
    use std::io::{BufReader, Cursor};
    use tempfile::TempDir;

    #[test]
    fn bounded_reader_discards_an_oversized_record_and_resumes() {
        let mut input = vec![b'x'; 64];
        input.extend_from_slice(b"\nkept\r\n");
        let reader = BufReader::with_capacity(8, Cursor::new(input));
        let mut lines = Vec::new();

        for_each_bounded_line(reader, 16, |line| {
            lines.push(line.to_vec());
            true
        })
        .unwrap();

        assert_eq!(lines, [b"kept".as_slice()]);
    }

    #[test]
    fn bounded_reader_stops_when_the_visitor_reaches_its_limit() {
        let reader = BufReader::new(Cursor::new(b"first\nsecond\nthird\n"));
        let mut lines = Vec::new();

        for_each_bounded_line(reader, 16, |line| {
            lines.push(line.to_vec());
            false
        })
        .unwrap();

        assert_eq!(lines, [b"first".as_slice()]);
    }

    #[test]
    fn free_form_sensitive_assignments_are_redacted() {
        for value in [
            "api_key=LIVE_SECRET",
            "apiKey=LIVE_SECRET",
            "access-key=LIVE_SECRET",
            "credential=LIVE_SECRET",
            "password: hunter2",
            "passwd=hunter2",
            "request failed: --passwd hunter2",
            "api_key: LIVE_SECRET",
            "client-secret: LIVE_SECRET",
            r#"request body: {"password":"hunter2"}"#,
            r#"request body: {\"password\":\"hunter2\"}"#,
            r#"request[\"password\"]=\"hunter2\""#,
            "request failed: --api-key LIVE_SECRET",
            r#"debug args: "--password" "hunter2""#,
            "Authorization:Basic dXNlcjpwYXNz",
            "-----BEGIN PRIVATE KEY-----\nLIVE_SECRET\n-----END PRIVATE KEY-----",
        ] {
            assert_eq!(sanitize_text(value), "[REDACTED]");
        }

        for key in ["privateKey", "private_key", "passphrase"] {
            assert_eq!(
                sanitize(serde_json::json!({ key: "LIVE_SECRET" }))[key],
                "[REDACTED]"
            );
        }
    }

    #[test]
    fn structured_argument_arrays_redact_sensitive_option_values() {
        let sanitized = sanitize(serde_json::json!({
            "args": [
                "--api-key",
                "LIVE_SECRET",
                "--output",
                "public.json",
                "--password",
                1234,
                "--token",
                "--verbose",
                "--api-key=INLINE_SECRET",
                "input.json"
            ]
        }));

        assert_eq!(sanitized["args"][0], "--api-key");
        assert_eq!(sanitized["args"][1], "[REDACTED]");
        assert_eq!(sanitized["args"][3], "public.json");
        assert_eq!(sanitized["args"][5], "[REDACTED]");
        assert_eq!(sanitized["args"][7], "--verbose");
        assert_eq!(sanitized["args"][8], "[REDACTED]");
        assert_eq!(sanitized["args"][9], "input.json");
    }

    #[test]
    fn structured_key_value_arrays_redact_sensitive_values() {
        let sanitized = sanitize(serde_json::json!({
            "headers": [
                ["x-api-key", "LIVE_SECRET"],
                ["content-type", "application/json"]
            ]
        }));

        assert_eq!(sanitized["headers"][0][0], "x-api-key");
        assert_eq!(sanitized["headers"][0][1], "[REDACTED]");
        assert_eq!(sanitized["headers"][1][1], "application/json");
    }

    #[test]
    fn every_url_in_free_form_text_is_sanitized() {
        assert_eq!(
            sanitize_text(
                "https://public.example/status|https://alice:hunter2@private.example/artifact"
            ),
            "https://public.example/status|https://[REDACTED]@private.example/artifact"
        );
        assert_eq!(
            sanitize_text("https://alice:hunter,2@example.com/artifact"),
            "https://[REDACTED]@example.com/artifact"
        );
        assert_eq!(
            sanitize_text("https://first.example?a=1|https://second.example/status"),
            "https://first.example|https://second.example/status"
        );
        assert_eq!(
            sanitize_text("fetch //alice:hunter2@private.example/artifact?download=secret"),
            "fetch //[REDACTED]@private.example/artifact"
        );
        assert_eq!(
            sanitize_text(
                "https://public.example/continue?redirect=https://private.example/reset/LIVE_SECRET"
            ),
            "https://public.example/continue"
        );
        assert_eq!(
            sanitize_text(
                "https://first.example?a=1,https://second.example/status?download=private"
            ),
            "https://first.example,https://second.example/status"
        );
        assert_eq!(
            sanitize_text(
                "https://first.example?redirect=https://nested.example/path;https://second.example?download=private"
            ),
            "https://first.example;https://second.example"
        );
    }

    #[test]
    fn diagnostic_bundles_redact_unknown_absolute_paths_on_all_platforms() {
        let value = serde_json::json!({
            "posix": "failed to open /Users/alice/company/model.json",
            "spaces": "failed to open /Users/alice/Client Merger/model.json",
            "punctuation": "failed to open /Users/alice/Client, Inc/model;v2.json",
            "closing_delimiters": "failed to open /Users/alice/Client) Merger/model].json",
            "wrapped": "failed to open (/Users/alice/company/model.json): permission denied",
            "drive": r"failed to open C:\Users\alice\company\model.json",
            "unc": r"failed to open \\fileserver\private\model.json",
            "known": r"C:\Users\alice\.morphir\store\tools",
            "near_prefix": "/Users/alice/.morphir-project/client/model.json",
            "with_error": "failed to open /Users/alice/company/model.json: permission denied",
        });
        let normalized = normalize_paths(
            value,
            &[
                (r"C:\Users\alice\.morphir", "$MORPHIR_HOME"),
                ("/Users/alice/.morphir", "$MORPHIR_HOME"),
            ],
        );

        for field in [
            "posix",
            "spaces",
            "punctuation",
            "closing_delimiters",
            "drive",
            "unc",
        ] {
            assert_eq!(
                normalized[field], "failed to open $ABSOLUTE_PATH",
                "field {field} should not expose an absolute path"
            );
        }
        assert_eq!(normalized["known"], r"$MORPHIR_HOME\store\tools");
        assert_eq!(normalized["near_prefix"], "$ABSOLUTE_PATH");
        assert_eq!(
            normalized["with_error"],
            "failed to open $ABSOLUTE_PATH: permission denied"
        );
        assert_eq!(
            normalized["wrapped"],
            "failed to open ($ABSOLUTE_PATH): permission denied"
        );
    }

    #[test]
    fn diagnostic_event_ingestion_retains_the_newest_event_at_the_byte_budget() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let first = serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "fields": { "operation_id": operation_id, "message": "first" }
        })
        .to_string();
        let second = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": { "operation_id": operation_id, "message": "second" }
        })
        .to_string();
        std::fs::write(
            temp_dir.path().join("events.jsonl"),
            format!("{first}\n{second}\n"),
        )
        .unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            first.len().max(second.len()),
            usize::MAX,
        );

        assert!(selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "second");
    }

    #[test]
    fn diagnostic_event_ingestion_keeps_terminal_events_across_log_roots() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let cli = temp_dir.path().join("a-cli");
        let desktop = temp_dir.path().join("z-desktop");
        std::fs::create_dir_all(&cli).unwrap();
        std::fs::create_dir_all(&desktop).unwrap();
        let started = serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "fields": { "operation_id": operation_id, "message": "started" }
        })
        .to_string();
        let failed = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": { "operation_id": operation_id, "message": "failed" }
        })
        .to_string();
        std::fs::write(cli.join("events.jsonl"), format!("{started}\n")).unwrap();
        std::fs::write(desktop.join("events.jsonl"), format!("{failed}\n")).unwrap();

        let selected = read_operation_events_with_limits(
            &[cli, desktop],
            operation_id,
            1,
            usize::MAX,
            usize::MAX,
        );

        assert!(selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "failed");
    }

    #[test]
    fn diagnostic_event_ingestion_deduplicates_overlapping_log_roots() {
        let temp_dir = TempDir::new().unwrap();
        let desktop = temp_dir.path().join("logs/desktop");
        std::fs::create_dir_all(&desktop).unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let event = serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "fields": { "operation_id": operation_id, "message": "once" }
        })
        .to_string();
        std::fs::write(desktop.join("events.jsonl"), format!("{event}\n")).unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().join("logs"), desktop],
            operation_id,
            10,
            event.len() * 2,
            usize::MAX,
        );

        assert!(!selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "once");
    }

    #[test]
    fn diagnostic_event_ingestion_reads_the_bounded_tail_of_large_logs() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let terminal = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": { "operation_id": operation_id, "message": "terminal" }
        })
        .to_string();
        std::fs::write(
            temp_dir.path().join("events.jsonl"),
            format!("{}\n{terminal}\n", "x".repeat(4096)),
        )
        .unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            usize::MAX,
            terminal.len() + 2,
        );

        assert!(selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "terminal");
    }
}
