//! Structured logging infrastructure for Morphir CLI.
//!
//! This module provides logging configuration that adheres to the logging standards:
//! - Console logs go to stderr (stdout is reserved for program output)
//! - File logs go to `MORPHIR_HOME/logs/cli/`
//! - Structured JSON format for file logs
//! - Configurable via environment variables and morphir.toml
//!
//! # Usage
//!
//! ```ignore
//! // Initialize from defaults and environment variables.
//! let _guard = logging::init_from_env();
//! ```

use std::{ffi::OsStr, path::PathBuf};
use tracing::Level;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{
    EnvFilter, Layer,
    fmt::{self, format::FmtSpan},
    layer::SubscriberExt,
    util::SubscriberInitExt,
};

#[derive(Debug, Clone, PartialEq, Eq)]
struct SessionLogLocation {
    directory: PathBuf,
    file_name: String,
    session_id: String,
}

fn session_log_location(
    timestamp: chrono::DateTime<chrono::Utc>,
    process_id: u32,
) -> SessionLogLocation {
    let timestamp_nanos = timestamp.timestamp_nanos_opt().unwrap_or_default() as u64;
    let session_id = format!("{process_id:x}-{timestamp_nanos:x}");
    SessionLogLocation {
        directory: PathBuf::from(timestamp.format("%Y-%m-%d").to_string()),
        file_name: format!(
            "{}-{process_id}-{session_id}.jsonl",
            timestamp.format("%Y%m%dT%H%M%S%.3fZ")
        ),
        session_id,
    }
}

/// Configuration for the logging system.
#[derive(Debug, Clone)]
pub struct LogConfig {
    /// Log level for console output
    pub console_level: Level,
    /// Log level for file output
    pub file_level: Level,
    /// Directory for log files
    pub log_dir: PathBuf,
    /// Whether to enable file logging
    pub file_logging: bool,
    /// Whether to use JSON format for file logs
    pub json_file_logs: bool,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            console_level: Level::INFO,
            file_level: Level::DEBUG,
            log_dir: default_log_dir(),
            file_logging: true,
            json_file_logs: true,
        }
    }
}

/// Determine the default log directory.
///
/// Priority:
/// 1. MORPHIR_LOG_DIR environment variable
/// 2. `logs/cli/` under the Morphir home directory
fn default_log_dir() -> PathBuf {
    let home = crate::home::MorphirHome::resolve().ok();
    log_dir_from(
        std::env::var_os("MORPHIR_LOG_DIR").as_deref(),
        home.as_ref(),
    )
}

fn log_dir_from(explicit: Option<&OsStr>, home: Option<&crate::home::MorphirHome>) -> PathBuf {
    explicit
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .or_else(|| home.map(crate::home::MorphirHome::cli_logs_dir))
        .unwrap_or_else(|| PathBuf::from(".morphir").join("logs").join("cli"))
}

/// Parse log level from environment variable or string.
fn parse_log_level(s: &str) -> Level {
    match s.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" | "warning" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    }
}

fn configured_log_level(
    canonical: Option<&str>,
    compatibility_alias: Option<&str>,
    fallback: Level,
) -> Level {
    canonical
        .or(compatibility_alias)
        .map(parse_log_level)
        .unwrap_or(fallback)
}

/// Initialize the logging system with the given configuration.
///
/// Returns a guard that must be kept alive for the duration of the program
/// to ensure file logs are flushed.
pub fn init(config: LogConfig) -> Option<WorkerGuard> {
    let console_filter = EnvFilter::new(format!("morphir={}", config.console_level));

    // Build the console layer (writes to stderr)
    let console_layer = fmt::layer()
        .with_target(false)
        .with_writer(std::io::stderr)
        .with_ansi(true)
        .compact()
        .with_filter(console_filter);

    if !config.file_logging {
        tracing_subscriber::registry().with(console_layer).init();
        return None;
    }

    let process_id = std::process::id();
    let session = session_log_location(chrono::Utc::now(), process_id);
    let session_directory = config.log_dir.join(&session.directory);
    let log_path = session_directory.join(&session.file_name);

    if let Err(e) = std::fs::create_dir_all(&session_directory) {
        eprintln!("Warning: Failed to create log directory: {}", e);
        tracing_subscriber::registry().with(console_layer).init();
        return None;
    }

    let file_appender = tracing_appender::rolling::never(&session_directory, &session.file_name);
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    // Build the file layer
    let file_layer = if config.json_file_logs {
        fmt::layer()
            .with_target(true)
            .with_writer(non_blocking)
            .with_ansi(false)
            .with_span_events(FmtSpan::CLOSE)
            .json()
            .with_filter(EnvFilter::new(format!("morphir={}", config.file_level)))
            .boxed()
    } else {
        fmt::layer()
            .with_target(true)
            .with_writer(non_blocking)
            .with_ansi(false)
            .with_span_events(FmtSpan::CLOSE)
            .with_filter(EnvFilter::new(format!("morphir={}", config.file_level)))
            .boxed()
    };

    tracing_subscriber::registry()
        .with(console_layer)
        .with(file_layer)
        .init();

    tracing::debug!(
        schema_version = 1,
        component = "cli",
        process_id,
        session_id = %session.session_id,
        event_name = "cli.session.start",
        log_path = %log_path.display(),
        "CLI file logging initialized"
    );

    Some(guard)
}

/// Initialize logging from environment variables.
///
/// Respects:
/// - MORPHIR_LOGGING__LEVEL: Console log level (trace, debug, info, warn, error)
/// - MORPHIR_LOGGING__FILE_LEVEL: File log level (trace, debug, info, warn, error)
/// - MORPHIR_LOG_DIR: Directory for log files
/// - MORPHIR_LOG_FILE: Enable file logging (true/false)
///
/// `MORPHIR_LOG_LEVEL` and `MORPHIR_LOG_FILE_LEVEL` remain compatibility aliases.
pub fn init_from_env() -> Option<WorkerGuard> {
    let mut config = LogConfig::default();

    let console_level = std::env::var("MORPHIR_LOGGING__LEVEL").ok();
    let legacy_console_level = std::env::var("MORPHIR_LOG_LEVEL").ok();
    config.console_level = configured_log_level(
        console_level.as_deref(),
        legacy_console_level.as_deref(),
        config.console_level,
    );

    let file_level = std::env::var("MORPHIR_LOGGING__FILE_LEVEL").ok();
    let legacy_file_level = std::env::var("MORPHIR_LOG_FILE_LEVEL").ok();
    config.file_level = configured_log_level(
        file_level.as_deref(),
        legacy_file_level.as_deref(),
        config.file_level,
    );

    if let Ok(dir) = std::env::var("MORPHIR_LOG_DIR") {
        config.log_dir = PathBuf::from(dir);
    }

    if let Ok(enable) = std::env::var("MORPHIR_LOG_FILE") {
        config.file_logging = enable.to_lowercase() == "true" || enable == "1";
    }

    init(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_log_level() {
        assert_eq!(parse_log_level("trace"), Level::TRACE);
        assert_eq!(parse_log_level("DEBUG"), Level::DEBUG);
        assert_eq!(parse_log_level("Info"), Level::INFO);
        assert_eq!(parse_log_level("WARN"), Level::WARN);
        assert_eq!(parse_log_level("warning"), Level::WARN);
        assert_eq!(parse_log_level("error"), Level::ERROR);
        assert_eq!(parse_log_level("unknown"), Level::INFO);
    }

    #[test]
    fn canonical_log_level_precedes_compatibility_alias() {
        assert_eq!(
            configured_log_level(Some("warn"), Some("trace"), Level::INFO),
            Level::WARN
        );
        assert_eq!(
            configured_log_level(None, Some("debug"), Level::INFO),
            Level::DEBUG
        );
        assert_eq!(configured_log_level(None, None, Level::INFO), Level::INFO);
    }

    #[test]
    fn default_file_logging_is_enabled() {
        assert!(LogConfig::default().file_logging);
    }

    #[test]
    fn cli_logs_live_in_morphir_home() {
        let home = crate::home::MorphirHome::resolve_from(
            Some(std::ffi::OsStr::new("/sandbox/morphir-home")),
            None,
        )
        .unwrap();

        assert_eq!(
            log_dir_from(None, Some(&home)),
            PathBuf::from("/sandbox/morphir-home/logs/cli")
        );
    }

    #[test]
    fn explicit_log_directory_overrides_morphir_home() {
        let home = crate::home::MorphirHome::resolve_from(
            Some(std::ffi::OsStr::new("/sandbox/morphir-home")),
            None,
        )
        .unwrap();

        assert_eq!(
            log_dir_from(Some(std::ffi::OsStr::new("/managed/logs")), Some(&home)),
            PathBuf::from("/managed/logs")
        );
    }

    #[test]
    fn session_logs_use_json_lines_in_a_daily_directory() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-08-29T14:03:12.456Z")
            .unwrap()
            .to_utc();

        let location = session_log_location(now, 42);

        assert_eq!(location.directory, PathBuf::from("2026-08-29"));
        assert!(location.file_name.starts_with("20260829T140312.456Z-42-"));
        assert!(location.file_name.ends_with(".jsonl"));
        assert!(!location.session_id.is_empty());
    }
}
