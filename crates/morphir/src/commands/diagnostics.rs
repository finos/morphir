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
const MAX_DIAGNOSTIC_DISCOVERY_ENTRIES: usize = 50_000;
const MAX_DIAGNOSTIC_LOG_FILES: usize = 4_096;

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

fn normalized_key(key: &str) -> String {
    key.chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn key_words(key: &str) -> Vec<String> {
    let characters = key.chars().collect::<Vec<_>>();
    let mut words = Vec::new();
    let mut word = String::new();

    for (index, character) in characters.iter().copied().enumerate() {
        if !character.is_ascii_alphanumeric() {
            if !word.is_empty() {
                words.push(std::mem::take(&mut word));
            }
            continue;
        }

        let previous = index
            .checked_sub(1)
            .and_then(|previous| characters.get(previous))
            .copied();
        let next = characters.get(index + 1).copied();
        let starts_camel_word = character.is_ascii_uppercase()
            && (previous.is_some_and(|previous| {
                previous.is_ascii_lowercase() || previous.is_ascii_digit()
            }) || (previous.is_some_and(|previous| previous.is_ascii_uppercase())
                && next.is_some_and(|next| next.is_ascii_lowercase())));

        if starts_camel_word && !word.is_empty() {
            words.push(std::mem::take(&mut word));
        }
        word.push(character.to_ascii_lowercase());
    }

    if !word.is_empty() {
        words.push(word);
    }
    words
}

fn sensitive_key(key: &str) -> bool {
    let has_auth_word = contains_auth_key_word(key);
    let normalized = normalized_key(key);
    let has_sensitive_token = normalized.contains("token") && !token_metadata_key(key);
    has_auth_word
        || has_sensitive_token
        || [
            "password",
            "passwd",
            "pwd",
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
        .any(|needle| normalized.contains(needle))
}

fn token_metadata_key(key: &str) -> bool {
    const METADATA_SUFFIXES: [&str; 3] = ["count", "kind", "position"];

    let normalized = normalized_key(key);
    METADATA_SUFFIXES
        .iter()
        .any(|suffix| normalized.ends_with(&format!("token{suffix}")))
}

fn contains_auth_key_word(key: &str) -> bool {
    key_words(key)
        .iter()
        .any(|word| matches!(word.as_str(), "auth" | "authentication"))
}

fn contains_sensitive_assignment(value: &str) -> bool {
    value
        .char_indices()
        .filter(|(_, character)| matches!(character, '=' | ':'))
        .any(|(separator, separator_character)| {
            let prefix = value[..separator]
                .trim_end()
                .trim_end_matches(['\'', '"', '\\', ']', ')', '}']);
            let key = prefix
                .chars()
                .rev()
                .take_while(|character| {
                    character.is_ascii_alphanumeric() || matches!(character, '_' | '-')
                })
                .collect::<String>()
                .chars()
                .rev()
                .collect::<String>();
            let key_start = prefix.len().saturating_sub(key.len());
            let key_context = prefix[..key_start].trim_end();
            let ordinary_token_diagnostic = normalized_key(&key) == "token"
                && key_context
                    .split_whitespace()
                    .next_back()
                    .is_some_and(|word| {
                        matches!(
                            word.to_ascii_lowercase().as_str(),
                            "expected" | "unexpected"
                        )
                    });
            let colon_value_looks_like_scalar = value[separator + 1..]
                .trim_start()
                .trim_start_matches(['\'', '"'])
                .chars()
                .next()
                .is_some_and(|character| !matches!(character, ')' | ']' | '}' | ',' | ';'));
            let colon_has_assignment_boundary = separator_character != ':'
                || key_start == 0
                || prefix[..key_start]
                    .chars()
                    .next_back()
                    .is_some_and(|character| {
                        matches!(character, '\'' | '"' | '\\' | '[' | '(' | '{' | ',' | ';')
                    })
                || (colon_value_looks_like_scalar && !ordinary_token_diagnostic);
            !key.is_empty() && sensitive_key(&key) && colon_has_assignment_boundary
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
    let tokens = value
        .split(|character: char| {
            character.is_whitespace()
                || matches!(
                    character,
                    '\'' | '"' | '\\' | '[' | ']' | '(' | ')' | '{' | '}' | ','
                )
        })
        .filter(|token| !token.is_empty())
        .collect::<Vec<_>>();
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

fn contains_serialized_sensitive_named_value(value: &str) -> bool {
    let tokens = value
        .split(|character: char| {
            character.is_whitespace()
                || matches!(
                    character,
                    '\'' | '"' | '\\' | '[' | ']' | '(' | ')' | '{' | '}' | ',' | ':' | '='
                )
        })
        .filter(|token| !token.is_empty())
        .collect::<Vec<_>>();
    let names_sensitive_key = tokens.windows(2).any(|pair| {
        matches!(normalized_key(pair[0]).as_str(), "name" | "key") && sensitive_key(pair[1])
    });
    let contains_value = tokens.windows(2).any(|pair| {
        matches!(normalized_key(pair[0]).as_str(), "value" | "values") && !pair[1].is_empty()
    });
    names_sensitive_key && contains_value
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

fn sensitive_pair_key(value: &str) -> bool {
    sensitive_key(value)
        && !sensitive_long_option(value)
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
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
    let token_start = url_scheme_start_before(value, authority_start.saturating_sub(3))
        .unwrap_or(authority_start.saturating_sub(3));
    let delimiter = value[authority_start..]
        .char_indices()
        .find(|(offset, character)| {
            character.is_whitespace()
                || matches!(character, '\'' | '"' | '<' | '>')
                || closes_wrapped_token(value, token_start, authority_start + offset, *character)
        })
        .map(|(index, _)| authority_start + index)
        .unwrap_or(value.len());
    value[authority_start..delimiter]
        .match_indices("://")
        .find_map(|(index, _)| {
            let start = url_scheme_start_before(value, authority_start + index)?;
            (start >= authority_start
                && top_level_url_separator_before(value, authority_start, start).is_some())
            .then_some(start)
        })
        .unwrap_or(delimiter)
}

fn closes_wrapped_token(
    value: &str,
    token_start: usize,
    candidate: usize,
    character: char,
) -> bool {
    let Some((opening, closing)) = value[..token_start]
        .chars()
        .next_back()
        .and_then(|opening| match opening {
            '(' => Some(('(', ')')),
            '[' => Some(('[', ']')),
            '{' => Some(('{', '}')),
            _ => None,
        })
    else {
        return false;
    };
    if character != closing {
        return false;
    }

    value[token_start..candidate]
        .chars()
        .fold(0_i64, |depth, nested| match nested {
            nested if nested == opening => depth.saturating_add(1),
            nested if nested == closing => depth.saturating_sub(1),
            _ => depth,
        })
        == 0
}

fn url_separator_before(value: &str, start: usize) -> Option<usize> {
    value[..start]
        .char_indices()
        .next_back()
        .filter(|(_, character)| matches!(character, '|' | ',' | ';'))
        .map(|(index, _)| index)
}

fn top_level_url_separator_before(
    value: &str,
    authority_start: usize,
    start: usize,
) -> Option<usize> {
    let separator = url_separator_before(value, start)?;
    (!value[authority_start..separator]
        .chars()
        .any(|character| matches!(character, '?' | '#')))
    .then_some(separator)
}

fn url_scheme_starts_at(value: &str, start: usize) -> bool {
    value[start..]
        .find("://")
        .is_some_and(|marker| url_scheme_start_before(value, start + marker) == Some(start))
}

fn is_url_path_boundary(character: char) -> bool {
    matches!(character, '/' | '\\' | '?' | '#')
}

fn redact_urls(value: &str) -> String {
    let mut redacted = value.to_owned();
    let mut search_from = 0;

    while let Some(marker) = redacted[search_from..].find("://") {
        let authority_start = search_from + marker + 3;
        let token_end = url_token_end(&redacted, authority_start);
        let authority_end = redacted[authority_start..token_end]
            .char_indices()
            .find(|(_, character)| is_url_path_boundary(*character))
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
            .find(|(_, character)| is_url_path_boundary(*character))
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
    let token_start = authority_start.saturating_sub(2);
    let delimiter = value[authority_start..]
        .char_indices()
        .find(|(offset, character)| {
            character.is_whitespace()
                || matches!(character, '\'' | '"' | '<' | '>' | '|')
                || closes_wrapped_token(value, token_start, authority_start + offset, *character)
        })
        .map(|(index, _)| authority_start + index)
        .unwrap_or(value.len());
    value[authority_start..delimiter]
        .match_indices("//")
        .find_map(|(index, _)| {
            let start = authority_start + index;
            top_level_url_separator_before(value, authority_start, start)
                .is_some()
                .then_some(start)
        })
        .unwrap_or(delimiter)
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
            .find(|(_, character)| is_url_path_boundary(*character))
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
            .find(|(_, character)| is_url_path_boundary(*character))
            .map(|(index, _)| authority_start + index)
        {
            let replacement_end = redacted[token_end..]
                .starts_with("//")
                .then(|| url_separator_before(&redacted, token_end))
                .flatten()
                .unwrap_or(token_end);
            redacted.replace_range(boundary..replacement_end, "");
            search_from = boundary;
        } else {
            search_from = scan_after;
        }
    }

    redacted
}

/// Sanitize free-form text before writing it to a correlated diagnostic event.
pub(crate) fn sanitize_text(value: &str) -> String {
    let value = if value.contains("://") {
        redact_urls(value)
    } else {
        value.to_owned()
    };
    let value = if value.contains("//") {
        redact_scheme_relative_urls(&value)
    } else {
        value
    };
    let lower = value.to_ascii_lowercase();
    if lower.contains("bearer ")
        || contains_authorization_header(&value)
        || ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_", "ghr_"]
            .iter()
            .any(|prefix| lower.contains(prefix))
        || (lower.contains("-----begin ") && lower.contains("private key-----"))
        || lower.contains("password=")
        || lower.contains("token=")
        || lower.contains("secret=")
        || contains_sensitive_assignment(&value)
        || contains_sensitive_option_pair(&value)
        || contains_serialized_sensitive_named_value(&value)
    {
        return "[REDACTED]".to_owned();
    }
    value
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
        && bytes
            .get(start + 1)
            .is_some_and(|next| !next.is_ascii_whitespace() && *next != b'/')
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
        serde_json::Value::Object(values) => {
            let redact_named_value = values.iter().any(|(field, value)| {
                matches!(normalized_key(field).as_str(), "name" | "key")
                    && value.as_str().is_some_and(sensitive_key)
            });
            let mut sanitized = serde_json::Map::new();
            for (key, value) in values {
                if excluded_diagnostic_container(&key) {
                    continue;
                }
                let value = if sensitive_key(&key)
                    || (redact_named_value
                        && matches!(normalized_key(&key).as_str(), "value" | "values"))
                {
                    serde_json::Value::String("[REDACTED]".to_owned())
                } else {
                    sanitize(value)
                };
                insert_unique_json_key(&mut sanitized, sanitize_text(&key), value);
            }
            serde_json::Value::Object(sanitized)
        }
        serde_json::Value::Array(values) => serde_json::Value::Array(sanitize_array(values)),
        serde_json::Value::String(value) => serde_json::Value::String(sanitize_text(&value)),
        value => value,
    }
}

fn excluded_diagnostic_container(key: &str) -> bool {
    excluded_sensitive_container(key) || excluded_project_payload_container(key)
}

fn excluded_project_payload_container(key: &str) -> bool {
    let exact_match = matches!(
        normalized_key(key).as_str(),
        "morphirir"
            | "irpayload"
            | "sourcecode"
            | "sourcefiles"
            | "sourcedocument"
            | "sourcedocuments"
            | "projectsources"
            | "generatedoutput"
            | "generatedcode"
            | "generatedfiles"
            | "generatedsources"
            | "generatedartifact"
            | "generatedartifacts"
    );
    let words = key_words(key);
    let contains_payload_words = words.windows(2).any(|words| {
        matches!(
            (words[0].as_str(), words[1].as_str()),
            ("morphir", "ir")
                | ("ir", "payload")
                | ("source", "code")
                | ("source", "files")
                | ("source", "document")
                | ("source", "documents")
                | ("project", "sources")
                | ("generated", "output")
                | ("generated", "code")
                | ("generated", "files")
                | ("generated", "sources")
                | ("generated", "artifact")
                | ("generated", "artifacts")
        )
    });
    let contains_clipboard_word = words.iter().any(|word| word.as_str() == "clipboard");
    exact_match || contains_payload_words || contains_clipboard_word
}

fn excluded_sensitive_container(key: &str) -> bool {
    let mut word = String::new();
    let mut previous: Option<char> = None;
    for character in key.chars() {
        let starts_camel_word = character.is_ascii_uppercase()
            && previous
                .is_some_and(|previous| previous.is_ascii_lowercase() || previous.is_ascii_digit());
        if (!character.is_ascii_alphanumeric() || starts_camel_word)
            && sensitive_container_word(&word)
        {
            return true;
        }
        if !character.is_ascii_alphanumeric() || starts_camel_word {
            word.clear();
        }
        if character.is_ascii_alphanumeric() {
            word.push(character.to_ascii_lowercase());
            previous = Some(character);
        } else {
            previous = None;
        }
    }
    sensitive_container_word(&word)
}

fn sensitive_container_word(word: &str) -> bool {
    matches!(
        word,
        "env" | "environment" | "environmentvariables" | "config" | "configuration" | "settings"
    )
}

fn insert_unique_json_key(
    values: &mut serde_json::Map<String, serde_json::Value>,
    key: String,
    value: serde_json::Value,
) {
    if !values.contains_key(&key) {
        values.insert(key, value);
        return;
    }
    let mut suffix = 2_u64;
    loop {
        let candidate = format!("{key}#{suffix}");
        if !values.contains_key(&candidate) {
            values.insert(candidate, value);
            return;
        }
        suffix = suffix.saturating_add(1);
    }
}

fn sanitize_array(values: Vec<serde_json::Value>) -> Vec<serde_json::Value> {
    let mut redact_next_option = false;
    let mut redact_next_pair_value = false;
    values
        .into_iter()
        .enumerate()
        .map(|(index, value)| {
            let long_option = value
                .as_str()
                .is_some_and(|value| value.trim_matches(['\'', '"']).starts_with("--"));
            if redact_next_pair_value || (redact_next_option && !long_option) {
                redact_next_pair_value = false;
                redact_next_option = false;
                return serde_json::Value::String("[REDACTED]".to_owned());
            }
            redact_next_option = value
                .as_str()
                .is_some_and(sensitive_long_option_consumes_next);
            redact_next_pair_value =
                index.is_multiple_of(2) && value.as_str().is_some_and(sensitive_pair_key);
            sanitize(value)
        })
        .collect()
}

fn normalize_paths(
    value: serde_json::Value,
    replacements: &[(&str, &'static str)],
) -> serde_json::Value {
    match value {
        serde_json::Value::Object(values) => {
            let mut normalized = serde_json::Map::new();
            for (key, value) in values {
                insert_unique_json_key(
                    &mut normalized,
                    normalize_path_text(&key, replacements),
                    normalize_paths(value, replacements),
                );
            }
            serde_json::Value::Object(normalized)
        }
        serde_json::Value::Array(values) => serde_json::Value::Array(
            values
                .into_iter()
                .map(|value| normalize_paths(value, replacements))
                .collect(),
        ),
        serde_json::Value::String(value) => {
            serde_json::Value::String(normalize_path_text(&value, replacements))
        }
        value => value,
    }
}

fn normalize_path_text(value: &str, replacements: &[(&str, &'static str)]) -> String {
    let normalized = replacements
        .iter()
        .fold(value.to_owned(), |value, (path, label)| {
            replace_known_path(&value, path, label)
        });
    redact_unknown_absolute_paths(&normalized)
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
    fields["operation_id"] == operation_id
        || fields["parent_operation_id"] == operation_id
        || event["span"]["operation_id"] == operation_id
        || event["spans"].as_array().is_some_and(|spans| {
            spans
                .iter()
                .any(|span| span["operation_id"] == operation_id)
        })
}

fn operation_log_roots(home: &crate::home::MorphirHome) -> [PathBuf; 2] {
    [
        crate::home::effective_cli_logs_dir(home),
        home.desktop_logs_dir(),
    ]
}

fn for_each_bounded_line<R, F>(mut reader: R, max_len: usize, mut visit: F) -> std::io::Result<bool>
where
    R: BufRead,
    F: FnMut(&[u8]) -> bool,
{
    let read_limit = u64::try_from(max_len).unwrap_or(u64::MAX).saturating_add(2);
    let mut omitted = false;
    loop {
        let mut line = Vec::with_capacity(max_len.min(8 * 1024));
        let read = reader
            .by_ref()
            .take(read_limit)
            .read_until(b'\n', &mut line)?;
        if read == 0 {
            return Ok(omitted);
        }

        let terminated = line.last() == Some(&b'\n');
        if terminated {
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
        }
        if line.len() > max_len {
            omitted = true;
            if !terminated {
                reader.skip_until(b'\n')?;
            }
            continue;
        }

        if !visit(&line) {
            return Ok(omitted);
        }
        if !terminated {
            return Ok(omitted);
        }
    }
}

fn bounded_tail_reader(
    mut file: File,
    snapshot_bytes: u64,
    scan_bytes: u64,
) -> std::io::Result<(BufReader<std::io::Take<File>>, bool)> {
    let scan_bytes = snapshot_bytes.min(scan_bytes);
    let start = snapshot_bytes.saturating_sub(scan_bytes);
    let starts_inside_line = if start > 0 {
        file.seek(SeekFrom::Start(start - 1))?;
        let mut previous = [0_u8; 1];
        file.read_exact(&mut previous)?;
        previous[0] != b'\n'
    } else {
        false
    };
    file.seek(SeekFrom::Start(start))?;
    Ok((BufReader::new(file.take(scan_bytes)), starts_inside_line))
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
    let discovered = discover_log_files(
        log_roots,
        MAX_DIAGNOSTIC_DISCOVERY_ENTRIES,
        MAX_DIAGNOSTIC_LOG_FILES,
    );
    let mut selected = read_operation_events_from_files(
        discovered.paths,
        operation_id,
        max_events,
        max_bytes,
        max_scan_bytes,
    );
    selected.truncated |= discovered.truncated;
    selected
}

struct DiscoveredLogFiles {
    paths: Vec<PathBuf>,
    truncated: bool,
}

#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
struct DiscoveredLogFile {
    modified: Option<std::time::SystemTime>,
    path: PathBuf,
}

fn retain_newest_log_file(
    retained: &mut BinaryHeap<Reverse<DiscoveredLogFile>>,
    candidate: DiscoveredLogFile,
    limit: usize,
) -> bool {
    retained.push(Reverse(candidate));
    if retained.len() <= limit {
        return false;
    }
    retained.pop();
    true
}

fn discover_log_files(
    log_roots: &[PathBuf],
    max_entries: usize,
    max_files: usize,
) -> DiscoveredLogFiles {
    let mut truncated = false;
    let mut log_files = BTreeSet::new();
    for (root_index, root) in log_roots.iter().enumerate() {
        let root_entry_limit = fair_share(max_entries, root_index, log_roots.len());
        let root_file_limit = fair_share(max_files, root_index, log_roots.len());
        let mut visited_entries = 0usize;
        let mut retained_files = BinaryHeap::new();
        let root = match root.canonicalize() {
            Ok(root) => root,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(_) => {
                truncated = true;
                continue;
            }
        };
        match root.metadata() {
            Ok(metadata) if metadata.is_dir() => {}
            Ok(_) | Err(_) => {
                truncated = true;
                continue;
            }
        }
        for entry in WalkDir::new(&root).follow_links(false) {
            if visited_entries >= root_entry_limit {
                truncated = true;
                break;
            }
            visited_entries = visited_entries.saturating_add(1);
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => {
                    truncated = true;
                    continue;
                }
            };
            if !entry.file_type().is_file()
                || !entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "jsonl")
            {
                continue;
            }
            let path = entry.into_path();
            let path = path.canonicalize().unwrap_or(path);
            let modified = path.metadata().and_then(|value| value.modified()).ok();
            if retain_newest_log_file(
                &mut retained_files,
                DiscoveredLogFile { modified, path },
                root_file_limit,
            ) {
                truncated = true;
            }
        }
        log_files.extend(
            retained_files
                .into_iter()
                .map(|Reverse(candidate)| candidate.path),
        );
    }
    let mut log_files = log_files.into_iter().collect::<Vec<_>>();
    log_files.sort_by(|left, right| {
        let modified = |path: &Path| path.metadata().and_then(|value| value.modified()).ok();
        modified(right)
            .cmp(&modified(left))
            .then_with(|| right.cmp(left))
    });
    DiscoveredLogFiles {
        paths: log_files,
        truncated,
    }
}

fn fair_share(total: usize, index: usize, parts: usize) -> usize {
    if parts == 0 {
        return 0;
    }
    total / parts + usize::from(index < total % parts)
}

fn read_operation_events_from_files(
    log_files: Vec<PathBuf>,
    operation_id: &str,
    max_events: usize,
    max_bytes: usize,
    max_scan_bytes: usize,
) -> DiagnosticEvents {
    let mut events = BinaryHeap::new();
    let mut retained_bytes = 0usize;
    let mut matched_events = 0usize;
    let mut truncated = false;
    let mut remaining_scan_bytes = max_scan_bytes;
    let total_log_files = log_files.len();
    for (file_index, path) in log_files.into_iter().enumerate() {
        if remaining_scan_bytes == 0 {
            truncated = true;
            break;
        }
        let Ok(file) = File::open(path) else {
            truncated = true;
            continue;
        };
        let Ok(file_bytes) = file.metadata().map(|metadata| metadata.len()) else {
            truncated = true;
            continue;
        };
        let files_remaining = total_log_files - file_index;
        let file_budget = remaining_scan_bytes.div_ceil(files_remaining);
        let scan_bytes = file_bytes.min(file_budget as u64);
        let start = file_bytes.saturating_sub(scan_bytes);
        let Ok((mut reader, starts_inside_line)) =
            bounded_tail_reader(file, file_bytes, scan_bytes)
        else {
            truncated = true;
            continue;
        };
        if start > 0 {
            truncated = true;
        }
        remaining_scan_bytes = remaining_scan_bytes.saturating_sub(scan_bytes as usize);
        if starts_inside_line && reader.skip_until(b'\n').is_err() {
            truncated = true;
            continue;
        }
        let scan_result = for_each_bounded_line(reader, 1024 * 1024, |line| {
            match serde_json::from_slice::<serde_json::Value>(line) {
                Ok(event) if belongs_to_operation(&event, operation_id) => {
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
                Ok(_) => {}
                Err(_) if !line.is_empty() => truncated = true,
                Err(_) => {}
            }
            true
        });
        if scan_result.is_err() || scan_result.is_ok_and(|omitted| omitted) {
            truncated = true;
        }
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

fn human_operation_event_lines(result: &OperationEvents) -> Vec<String> {
    let mut lines = Vec::with_capacity(result.events.len().saturating_add(1));
    if result.truncated {
        lines.push(
            "Diagnostic results are incomplete because some local events could not be read or retained."
                .to_owned(),
        );
    }
    if result.events.is_empty() {
        lines.push(format!("No local events found for {}", result.operation_id));
    } else {
        lines.extend(result.events.iter().map(|event| {
            let timestamp = event["timestamp"].as_str().unwrap_or("unknown-time");
            let level = event["level"].as_str().unwrap_or("UNKNOWN");
            let name = event["fields"]["event_name"]
                .as_str()
                .unwrap_or("unknown-event");
            format!("{timestamp} {level} {name}")
        }));
    }
    lines
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
    } else {
        for line in human_operation_event_lines(&result) {
            println!("{line}");
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
        DiscoveredLogFile, OperationEvents, belongs_to_operation, bounded_tail_reader,
        discover_log_files, for_each_bounded_line, human_operation_event_lines, normalize_paths,
        read_operation_events_from_files, read_operation_events_with_limits,
        retain_newest_log_file, sanitize, sanitize_text,
    };
    use std::cmp::Reverse;
    use std::collections::{BTreeSet, BinaryHeap};
    use std::io::{BufReader, Cursor};
    use std::time::{Duration, SystemTime};
    use tempfile::TempDir;

    fn create_directory_link(
        target: &std::path::Path,
        link: &std::path::Path,
    ) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(target, link)
        }
        #[cfg(windows)]
        {
            std::os::windows::fs::symlink_dir(target, link)
        }
    }

    #[test]
    fn bounded_reader_discards_an_oversized_record_and_resumes() {
        let mut input = vec![b'x'; 64];
        input.extend_from_slice(b"\nkept\r\n");
        let reader = BufReader::with_capacity(8, Cursor::new(input));
        let mut lines = Vec::new();

        let omitted = for_each_bounded_line(reader, 16, |line| {
            lines.push(line.to_vec());
            true
        })
        .unwrap();

        assert!(omitted);
        assert_eq!(lines, [b"kept".as_slice()]);
    }

    #[test]
    fn bounded_reader_stops_when_the_visitor_reaches_its_limit() {
        let reader = BufReader::new(Cursor::new(b"first\nsecond\nthird\n"));
        let mut lines = Vec::new();

        let omitted = for_each_bounded_line(reader, 16, |line| {
            lines.push(line.to_vec());
            false
        })
        .unwrap();

        assert!(!omitted);
        assert_eq!(lines, [b"first".as_slice()]);
    }

    #[test]
    fn bounded_tail_reader_stops_at_the_snapshotted_file_length() {
        let temp_dir = TempDir::new().unwrap();
        let path = temp_dir.path().join("events.jsonl");
        std::fs::write(&path, b"snapshotted\n").unwrap();
        let file = std::fs::File::open(&path).unwrap();
        let snapshot_bytes = file.metadata().unwrap().len();
        let mut writer = std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .unwrap();
        std::io::Write::write_all(&mut writer, b"appended\n").unwrap();

        let (reader, starts_inside_line) =
            bounded_tail_reader(file, snapshot_bytes, snapshot_bytes).unwrap();
        let mut lines = Vec::new();
        for_each_bounded_line(reader, 64, |line| {
            lines.push(line.to_vec());
            true
        })
        .unwrap();

        assert!(!starts_inside_line);
        assert_eq!(lines, [b"snapshotted".as_slice()]);
    }

    #[test]
    fn free_form_sensitive_assignments_are_redacted() {
        for value in [
            "api_key=LIVE_SECRET",
            "apiKey=LIVE_SECRET",
            "access-key=LIVE_SECRET",
            "credential=LIVE_SECRET",
            "password: hunter2",
            "request password: hunter2",
            "passwd=hunter2",
            "pwd=hunter2",
            "request failed: --passwd hunter2",
            "request failed: --pwd hunter2",
            "api_key: LIVE_SECRET",
            "client-secret: LIVE_SECRET",
            r#"request body: {"password":"hunter2"}"#,
            r#"request body: {\"password\":\"hunter2\"}"#,
            r#"request[\"password\"]=\"hunter2\""#,
            "request failed: --api-key LIVE_SECRET",
            r#"debug args: "--password" "hunter2""#,
            r#"args=["--password","hunter2"]"#,
            r#"headers=[{"name":"x-api-key","value":"LIVE_SECRET"}]"#,
            r#"headers=[{\"key\":\"authorization\",\"values\":[\"LIVE_SECRET\"]}]"#,
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
        let public_header = r#"headers=[{"name":"content-type","value":"application/json"}]"#;
        assert_eq!(sanitize_text(public_header), public_header);
        assert_eq!(
            sanitize_text("unexpected token: ')'"),
            "unexpected token: ')'"
        );
        assert_eq!(
            sanitize_text("unexpected token: Identifier"),
            "unexpected token: Identifier"
        );
    }

    #[test]
    fn every_github_token_format_is_redacted_from_free_form_text() {
        for prefix in ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_", "ghr_"] {
            assert_eq!(
                sanitize_text(&format!("request failed with {prefix}LIVE_SECRET")),
                "[REDACTED]"
            );
        }
    }

    #[test]
    fn structured_token_metadata_preserves_values_and_types() {
        let input = serde_json::json!({
            "tokenCount": 42,
            "tokenKind": "identifier",
            "tokenPosition": { "line": 3, "column": 14 }
        });

        assert_eq!(sanitize(input.clone()), input);
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
            ],
            "compact": ["--api-key=INLINE_SECRET", "input.json"]
        }));

        assert_eq!(sanitized["args"][0], "--api-key");
        assert_eq!(sanitized["args"][1], "[REDACTED]");
        assert_eq!(sanitized["args"][3], "public.json");
        assert_eq!(sanitized["args"][5], "[REDACTED]");
        assert_eq!(sanitized["args"][7], "--verbose");
        assert_eq!(sanitized["args"][8], "[REDACTED]");
        assert_eq!(sanitized["args"][9], "input.json");
        assert_eq!(sanitized["compact"][0], "[REDACTED]");
        assert_eq!(sanitized["compact"][1], "input.json");
    }

    #[test]
    fn human_diagnostic_output_reports_an_incomplete_empty_search() {
        let lines = human_operation_event_lines(&OperationEvents {
            operation_id: "op-123e4567-e89b-42d3-a456-426614174000".to_owned(),
            truncated: true,
            events: Vec::new(),
        });

        assert_eq!(
            lines,
            [
                "Diagnostic results are incomplete because some local events could not be read or retained.",
                "No local events found for op-123e4567-e89b-42d3-a456-426614174000"
            ]
        );
    }

    #[test]
    fn structured_key_value_arrays_redact_sensitive_values() {
        let sanitized = sanitize(serde_json::json!({
            "headers": [
                ["x-api-key", "LIVE_SECRET"],
                ["content-type", "application/json"],
                ["password=LIVE_SECRET", "input.json"]
            ],
            "flatHeaders": [
                "x-api-key", "FLAT_SECRET",
                "content-type", "application/json"
            ]
        }));

        assert_eq!(sanitized["headers"][0][0], "x-api-key");
        assert_eq!(sanitized["headers"][0][1], "[REDACTED]");
        assert_eq!(sanitized["headers"][1][1], "application/json");
        assert_eq!(sanitized["headers"][2][0], "[REDACTED]");
        assert_eq!(sanitized["headers"][2][1], "input.json");
        assert_eq!(sanitized["flatHeaders"][0], "x-api-key");
        assert_eq!(sanitized["flatHeaders"][1], "[REDACTED]");
        assert_eq!(sanitized["flatHeaders"][2], "content-type");
        assert_eq!(sanitized["flatHeaders"][3], "application/json");
    }

    #[test]
    fn structured_named_values_redact_sensitive_values() {
        let sanitized = sanitize(serde_json::json!({
            "headers": [
                { "name": "x-api-key", "value": "LIVE_SECRET" },
                { "key": "authorization", "value": "Bearer LIVE_SECRET" },
                { "name": "x-api-key", "values": ["LIVE_SECRET"] },
                { "name": "content-type", "value": "application/json" }
            ]
        }));

        assert_eq!(sanitized["headers"][0]["name"], "x-api-key");
        assert_eq!(sanitized["headers"][0]["value"], "[REDACTED]");
        assert_eq!(sanitized["headers"][1]["key"], "authorization");
        assert_eq!(sanitized["headers"][1]["value"], "[REDACTED]");
        assert_eq!(sanitized["headers"][2]["values"], "[REDACTED]");
        assert_eq!(sanitized["headers"][3]["value"], "application/json");
    }

    #[test]
    fn structured_object_keys_are_sanitized_without_losing_collisions() {
        let sanitized = sanitize(serde_json::json!({
            "requests": {
                "https://alice:hunter2@private.example/path": 200,
                "https://bob:swordfish@private.example/path": 201
            }
        }));
        let requests = sanitized["requests"].as_object().unwrap();

        assert_eq!(requests.len(), 2);
        assert_eq!(requests["https://[REDACTED]@private.example"], 200);
        assert_eq!(requests["https://[REDACTED]@private.example#2"], 201);
    }

    #[test]
    fn operation_events_match_the_current_tracing_span() {
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let event = serde_json::json!({
            "fields": { "message": "backup cleanup failed" },
            "span": { "name": "cli.operation", "operation_id": operation_id }
        });

        assert!(belongs_to_operation(&event, operation_id));
    }

    #[test]
    fn structured_auth_keys_are_redacted_without_redacting_author_fields() {
        let sanitized = sanitize(serde_json::json!({
            "_auth": "BASE64_CREDENTIAL",
            "proxyAuth": "PROXY_CREDENTIAL",
            "serviceAuthentication": "SERVICE_CREDENTIAL",
            "environment": {
                "NPM_CONFIG__AUTH": "NAMESPACED_CREDENTIAL",
                "DEPLOYMENT_LICENSE": "LIVE_SECRET"
            },
            "process.env": {
                "DEPLOYMENT_LICENSE": "NAMESPACED_SECRET"
            },
            "ENV": {
                "DEPLOYMENT_LICENSE": "UPPERCASE_SECRET"
            },
            "configuration": {
                "endpoint": "internal.example.test"
            },
            "runtimeConfig": {
                "endpoint": "internal.example.test"
            },
            "settings": {
                "DEPLOYMENT_LICENSE": "SETTINGS_SECRET"
            },
            "appSettings": {
                "DEPLOYMENT_LICENSE": "NAMESPACED_SETTINGS_SECRET"
            },
            "env": "DEPLOYMENT_LICENSE=SCALAR_SECRET",
            "config": "endpoint=internal.example.test",
            "envelope": {
                "message": "public"
            },
            "author": "Ada"
        }));

        assert_eq!(sanitized["_auth"], "[REDACTED]");
        assert_eq!(sanitized["proxyAuth"], "[REDACTED]");
        assert_eq!(sanitized["serviceAuthentication"], "[REDACTED]");
        assert!(sanitized.get("environment").is_none());
        assert!(sanitized.get("process.env").is_none());
        assert!(sanitized.get("ENV").is_none());
        assert!(sanitized.get("configuration").is_none());
        assert!(sanitized.get("runtimeConfig").is_none());
        assert!(sanitized.get("settings").is_none());
        assert!(sanitized.get("appSettings").is_none());
        assert!(sanitized.get("env").is_none());
        assert!(sanitized.get("config").is_none());
        assert_eq!(sanitized["envelope"]["message"], "public");
        assert_eq!(sanitized["author"], "Ada");
    }

    #[test]
    fn structured_project_payload_containers_are_excluded() {
        let sanitized = sanitize(serde_json::json!({
            "morphirIr": { "formatVersion": 3, "distribution": "PRIVATE_IR" },
            "frontend.morphirIR": "PRIVATE_NAMESPACED_IR",
            "ir_payload": "PRIVATE_IR_PAYLOAD",
            "sourceCode": "module Private exposing (..)",
            "compilerSourceCode": "module AlsoPrivate exposing (..)",
            "compilerSourceDocuments": ["PRIVATE_SOURCE_DOCUMENT"],
            "projectSources": ["PRIVATE_SOURCE"],
            "generatedOutput": { "Private.java": "PRIVATE_GENERATED_OUTPUT" },
            "backendGeneratedOutput": { "Private.scala": "PRIVATE_GENERATED_OUTPUT" },
            "generatedCode": "PRIVATE_GENERATED_CODE",
            "backendGeneratedArtifacts": ["PRIVATE_GENERATED_ARTIFACT"],
            "clipboard": "PRIVATE_COPIED_TEXT",
            "desktopClipboardText": "PRIVATE_COPIED_TEXT",
            "sourceUrl": "https://public.example/status",
            "outputPath": "dist"
        }));

        for field in [
            "morphirIr",
            "frontend.morphirIR",
            "ir_payload",
            "sourceCode",
            "compilerSourceCode",
            "compilerSourceDocuments",
            "projectSources",
            "generatedOutput",
            "backendGeneratedOutput",
            "generatedCode",
            "backendGeneratedArtifacts",
            "clipboard",
            "desktopClipboardText",
        ] {
            assert!(
                sanitized.get(field).is_none(),
                "field {field} should be excluded"
            );
        }
        assert_eq!(sanitized["sourceUrl"], "https://public.example");
        assert_eq!(sanitized["outputPath"], "dist");
    }

    #[test]
    fn every_url_in_free_form_text_is_sanitized() {
        assert_eq!(
            sanitize_text("reset link: https://private.example/reset/LIVE_SECRET"),
            "reset link: https://private.example"
        );
        assert_eq!(
            sanitize_text(r"reset link: https://private.example\reset\LIVE_SECRET"),
            "reset link: https://private.example"
        );
        assert_eq!(
            sanitize_text(
                "https://public.example/status|https://alice:hunter2@private.example/artifact"
            ),
            "https://public.example|https://[REDACTED]@private.example"
        );
        assert_eq!(
            sanitize_text("https://alice:hunter,2@example.com/artifact"),
            "https://[REDACTED]@example.com"
        );
        assert_eq!(
            sanitize_text("https://first.example?a=1|https://second.example/status"),
            "https://first.example"
        );
        assert_eq!(
            sanitize_text("fetch //alice:hunter2@private.example/artifact?download=secret"),
            "fetch //[REDACTED]@private.example"
        );
        assert_eq!(
            sanitize_text(
                "https://public.example/continue?redirect=https://private.example/reset/LIVE_SECRET"
            ),
            "https://public.example"
        );
        assert_eq!(
            sanitize_text(
                "https://first.example?a=1,https://second.example/status?download=private"
            ),
            "https://first.example"
        );
        assert_eq!(
            sanitize_text(
                "https://first.example?redirect=https://nested.example/path;https://second.example?download=private"
            ),
            "https://first.example"
        );
        assert_eq!(
            sanitize_text(
                "https://public.example/continue?urls=https://a.test/x,https://private.example/reset/LIVE_SECRET"
            ),
            "https://public.example"
        );
        assert_eq!(
            sanitize_text("request (https://example.test/status?token=x),retrying"),
            "request (https://example.test),retrying"
        );
        assert_eq!(
            sanitize_text("request (https://private.example/reset(foo)/LIVE_SECRET),retrying"),
            "request (https://private.example),retrying"
        );
        assert_eq!(
            sanitize_text("//first.example?a=1,//second.example/status"),
            "//first.example"
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
            "prose": "completed 1 / 2 phases; retrying",
            "files": {
                "/Users/alice/private/model.json": "failed",
                r"C:\Users\alice\.morphir\store\tools": "known"
            },
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
        assert_eq!(normalized["prose"], "completed 1 / 2 phases; retrying");
        assert_eq!(
            normalized["with_error"],
            "failed to open $ABSOLUTE_PATH: permission denied"
        );
        assert_eq!(
            normalized["wrapped"],
            "failed to open ($ABSOLUTE_PATH): permission denied"
        );
        assert_eq!(normalized["files"]["$ABSOLUTE_PATH"], "failed");
        assert_eq!(normalized["files"][r"$MORPHIR_HOME\store\tools"], "known");
    }

    #[test]
    fn diagnostic_event_ingestion_marks_oversized_records_as_truncated() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let oversized = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": {
                "operation_id": operation_id,
                "message": "x".repeat(1024 * 1024)
            }
        })
        .to_string();
        std::fs::write(
            temp_dir.path().join("events.jsonl"),
            format!("{oversized}\n"),
        )
        .unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            usize::MAX,
            usize::MAX,
        );

        assert!(selected.truncated);
        assert!(selected.events.is_empty());
    }

    #[test]
    fn diagnostic_log_discovery_stops_at_entry_and_candidate_limits() {
        let temp_dir = TempDir::new().unwrap();
        for name in ["first.jsonl", "second.jsonl", "third.jsonl"] {
            std::fs::write(temp_dir.path().join(name), b"\n").unwrap();
        }

        let candidate_limited = discover_log_files(&[temp_dir.path().to_path_buf()], usize::MAX, 2);
        assert!(candidate_limited.truncated);
        assert_eq!(candidate_limited.paths.len(), 2);

        let entry_limited = discover_log_files(&[temp_dir.path().to_path_buf()], 1, 10);
        assert!(entry_limited.truncated);
        assert!(entry_limited.paths.is_empty());
    }

    #[test]
    fn diagnostic_log_discovery_reserves_capacity_for_each_root() {
        let first_root = TempDir::new().unwrap();
        let second_root = TempDir::new().unwrap();
        for root in [&first_root, &second_root] {
            for name in ["first.jsonl", "second.jsonl"] {
                std::fs::write(root.path().join(name), b"\n").unwrap();
            }
        }

        let discovered = discover_log_files(
            &[
                first_root.path().to_path_buf(),
                second_root.path().to_path_buf(),
            ],
            usize::MAX,
            2,
        );

        assert!(discovered.truncated);
        assert_eq!(discovered.paths.len(), 2);
        let first_root = first_root.path().canonicalize().unwrap();
        let second_root = second_root.path().canonicalize().unwrap();
        assert!(
            discovered
                .paths
                .iter()
                .any(|path| path.starts_with(&first_root))
        );
        assert!(
            discovered
                .paths
                .iter()
                .any(|path| path.starts_with(&second_root))
        );
    }

    #[test]
    fn diagnostic_log_discovery_keeps_the_newest_candidates_within_each_limit() {
        let mut retained = BinaryHeap::new();
        for (name, age) in [("old.jsonl", 1), ("new.jsonl", 3), ("middle.jsonl", 2)] {
            retain_newest_log_file(
                &mut retained,
                DiscoveredLogFile {
                    modified: Some(SystemTime::UNIX_EPOCH + Duration::from_secs(age)),
                    path: name.into(),
                },
                2,
            );
        }

        let paths = retained
            .into_iter()
            .map(|Reverse(file)| file.path)
            .collect::<BTreeSet<_>>();
        assert_eq!(
            paths,
            BTreeSet::from(["middle.jsonl".into(), "new.jsonl".into()])
        );
    }

    #[test]
    fn diagnostic_event_ingestion_marks_malformed_records_as_truncated() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        std::fs::write(
            temp_dir.path().join("events.jsonl"),
            br#"{"timestamp":"2026-08-30T03:04:06Z","fields":{"operation_id":"op-123e4567-e89b-42d3-a456-426614174000""#,
        )
        .unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            usize::MAX,
            usize::MAX,
        );

        assert!(selected.truncated);
        assert!(selected.events.is_empty());
    }

    #[test]
    fn diagnostic_event_ingestion_marks_unreadable_candidates_as_truncated() {
        let temp_dir = TempDir::new().unwrap();
        let selected = read_operation_events_from_files(
            vec![temp_dir.path().join("vanished.jsonl")],
            "op-123e4567-e89b-42d3-a456-426614174000",
            10,
            usize::MAX,
            usize::MAX,
        );

        assert!(selected.truncated);
        assert!(selected.events.is_empty());
    }

    #[test]
    fn diagnostic_event_ingestion_treats_missing_optional_roots_as_empty() {
        let temp_dir = TempDir::new().unwrap();
        let cli = temp_dir.path().join("cli");
        let desktop = temp_dir.path().join("desktop-not-created");
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        std::fs::create_dir_all(&cli).unwrap();
        let event = serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "fields": { "operation_id": operation_id, "message": "complete" }
        })
        .to_string();
        std::fs::write(cli.join("events.jsonl"), format!("{event}\n")).unwrap();

        let selected = read_operation_events_with_limits(
            &[cli, desktop],
            operation_id,
            10,
            usize::MAX,
            usize::MAX,
        );

        assert!(!selected.truncated);
        assert_eq!(selected.events.len(), 1);
    }

    #[test]
    fn diagnostic_event_ingestion_follows_only_the_selected_root_link() {
        let temp_dir = TempDir::new().unwrap();
        let actual = temp_dir.path().join("actual");
        let selected_root = temp_dir.path().join("configured");
        let nested_actual = temp_dir.path().join("nested-actual");
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        std::fs::create_dir_all(&actual).unwrap();
        std::fs::create_dir_all(&nested_actual).unwrap();
        let event = |message| {
            serde_json::json!({
                "timestamp": "2026-08-30T03:04:05Z",
                "fields": { "operation_id": operation_id, "message": message }
            })
            .to_string()
        };
        std::fs::write(actual.join("events.jsonl"), format!("{}\n", event("root"))).unwrap();
        std::fs::write(
            nested_actual.join("events.jsonl"),
            format!("{}\n", event("nested")),
        )
        .unwrap();
        if create_directory_link(&nested_actual, &actual.join("nested")).is_err()
            || create_directory_link(&actual, &selected_root).is_err()
        {
            return;
        }

        let selected = read_operation_events_with_limits(
            &[selected_root],
            operation_id,
            10,
            usize::MAX,
            usize::MAX,
        );

        assert!(!selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "root");
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

    #[test]
    fn diagnostic_event_ingestion_keeps_a_record_at_the_exact_tail_boundary() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let terminal = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": { "operation_id": operation_id, "message": "terminal" }
        })
        .to_string();
        std::fs::write(
            temp_dir.path().join("events.jsonl"),
            format!("discarded\n{terminal}\n"),
        )
        .unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            usize::MAX,
            terminal.len() + 1,
        );

        assert!(selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "terminal");
    }

    #[test]
    fn diagnostic_scan_budget_reserves_a_tail_for_each_log() {
        let temp_dir = TempDir::new().unwrap();
        let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
        let older = temp_dir.path().join("older.jsonl");
        let newer = temp_dir.path().join("newer.jsonl");
        let terminal = serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "fields": { "operation_id": operation_id, "message": "terminal" }
        })
        .to_string();
        std::fs::write(&older, format!("{terminal}\n")).unwrap();
        std::fs::write(&newer, format!("{}\n", "x".repeat(4096))).unwrap();

        let selected = read_operation_events_with_limits(
            &[temp_dir.path().to_path_buf()],
            operation_id,
            10,
            usize::MAX,
            (terminal.len() + 2) * 2,
        );

        assert!(selected.truncated);
        assert_eq!(selected.events.len(), 1);
        assert_eq!(selected.events[0]["fields"]["message"], "terminal");
    }
}
