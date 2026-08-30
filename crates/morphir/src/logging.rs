//! Structured logging infrastructure for Morphir CLI.
//!
//! This module provides logging configuration that adheres to the logging standards:
//! - Console logs go to stderr (stdout is reserved for program output)
//! - File logs go to `MORPHIR_HOME/logs/cli/`
//! - Structured JSON format for file logs
//! - Configurable at startup via environment variables
//!
//! # Usage
//!
//! ```ignore
//! // Initialize from defaults and environment variables.
//! let operation_id = observability::OperationId::new();
//! let _guard = logging::init_from_env(&operation_id);
//! ```

mod retention;

use fs2::FileExt as _;
use retention::{
    DEFAULT_LOG_RETENTION, DEFAULT_MAX_LOG_BYTES, active_marker_path, enforce_log_retention,
};
use std::{
    ffi::OsStr,
    fs, io,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};
use tracing::Level;
use tracing_appender::{
    non_blocking::WorkerGuard,
    rolling::{InitError, RollingFileAppender, Rotation},
};
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

/// Keeps the non-blocking writer alive and marks its session as completed when
/// the CLI exits normally.
pub struct LogGuard {
    worker: Option<WorkerGuard>,
    marker_file: Option<fs::File>,
    active_marker: PathBuf,
    log_path: PathBuf,
    session_id: String,
}

impl LogGuard {
    /// Exact JSON Lines file for the current CLI process.
    pub fn log_path(&self) -> &Path {
        &self.log_path
    }

    fn session_id(&self) -> &str {
        &self.session_id
    }
}

impl Drop for LogGuard {
    fn drop(&mut self) {
        drop(self.worker.take());
        if let Some(marker_file) = self.marker_file.take() {
            if let Err(error) = fs2::FileExt::unlock(&marker_file) {
                eprintln!("Warning: Failed to unlock CLI log session marker: {error}");
            }
            drop(marker_file);
        }
        if let Err(error) = fs::remove_file(&self.active_marker)
            && error.kind() != io::ErrorKind::NotFound
        {
            eprintln!("Warning: Failed to mark CLI log session complete: {error}");
        }
    }
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

fn create_file_appender(
    directory: &Path,
    file_name: &str,
) -> Result<RollingFileAppender, InitError> {
    RollingFileAppender::builder()
        .rotation(Rotation::NEVER)
        .filename_prefix(file_name)
        .build(directory)
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
    /// Maximum age for completed session logs
    pub retention: Duration,
    /// Target maximum bytes for completed CLI session logs
    pub max_bytes: u64,
}

impl Default for LogConfig {
    fn default() -> Self {
        let log_dir = default_log_dir();
        Self {
            console_level: Level::INFO,
            file_level: Level::DEBUG,
            file_logging: log_dir.is_some(),
            log_dir: log_dir.unwrap_or_default(),
            json_file_logs: true,
            retention: DEFAULT_LOG_RETENTION,
            max_bytes: DEFAULT_MAX_LOG_BYTES,
        }
    }
}

/// Determine the default log directory.
///
/// Priority:
/// 1. MORPHIR_LOG_DIR environment variable
/// 2. `logs/cli/` under the Morphir home directory
fn default_log_dir() -> Option<PathBuf> {
    let home = crate::home::MorphirHome::resolve().ok();
    log_dir_from(
        std::env::var_os("MORPHIR_LOG_DIR").as_deref(),
        home.as_ref(),
    )
}

fn log_dir_from(
    explicit: Option<&OsStr>,
    home: Option<&crate::home::MorphirHome>,
) -> Option<PathBuf> {
    explicit
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .or_else(|| home.map(crate::home::MorphirHome::cli_logs_dir))
}

fn apply_log_dir_override(current: PathBuf, explicit: Option<&OsStr>) -> PathBuf {
    explicit
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .unwrap_or(current)
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

fn configured_bool(value: Option<&str>, fallback: bool) -> bool {
    match value.map(str::trim) {
        Some(value) if value.eq_ignore_ascii_case("true") || value == "1" => true,
        Some(value) if value.eq_ignore_ascii_case("false") || value == "0" => false,
        _ => fallback,
    }
}

/// Initialize the logging system with the given configuration.
///
/// Returns a guard that must be kept alive for the duration of the program
/// to ensure file logs are flushed.
pub fn init(
    config: LogConfig,
    operation_id: &crate::observability::OperationId,
) -> Option<LogGuard> {
    let console_filter = EnvFilter::new(format!("morphir={}", config.console_level));

    // Build the console layer (writes to stderr)
    let console_layer = fmt::layer()
        .with_target(false)
        .with_writer(std::io::stderr)
        .with_ansi(true)
        .compact()
        .with_filter(console_filter);

    if !config.file_logging || config.log_dir.as_os_str().is_empty() {
        tracing_subscriber::registry().with(console_layer).init();
        return None;
    }

    let process_id = std::process::id();
    let session = session_log_location(chrono::Utc::now(), process_id);
    let session_directory = config.log_dir.join(&session.directory);
    let log_path = session_directory.join(&session.file_name);

    let retention = enforce_log_retention(
        &config.log_dir,
        SystemTime::now(),
        config.retention,
        config.max_bytes,
    );

    if let Err(e) = std::fs::create_dir_all(&session_directory) {
        eprintln!("Warning: Failed to create log directory: {}", e);
        tracing_subscriber::registry().with(console_layer).init();
        return None;
    }

    let active_marker = active_marker_path(&log_path);
    let marker_file = match fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&active_marker)
    {
        Ok(file) => file,
        Err(error) => {
            eprintln!("Warning: Failed to create CLI log session marker: {error}");
            tracing_subscriber::registry().with(console_layer).init();
            return None;
        }
    };
    if let Err(error) = marker_file.try_lock_exclusive() {
        eprintln!("Warning: Failed to lock CLI log session marker: {error}");
        drop(marker_file);
        let _ = fs::remove_file(&active_marker);
        tracing_subscriber::registry().with(console_layer).init();
        return None;
    }

    let file_appender = match create_file_appender(&session_directory, &session.file_name) {
        Ok(appender) => appender,
        Err(error) => {
            eprintln!("Warning: Failed to create CLI log file: {error}");
            drop(marker_file);
            if let Err(error) = fs::remove_file(&active_marker)
                && error.kind() != io::ErrorKind::NotFound
            {
                eprintln!("Warning: Failed to remove CLI log session marker: {error}");
            }
            tracing_subscriber::registry().with(console_layer).init();
            return None;
        }
    };
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
        operation_id = %operation_id,
        event_name = "cli.session.start",
        log_path = %log_path.display(),
        "CLI file logging initialized"
    );

    tracing::debug!(
        schema_version = 1,
        component = "cli",
        process_id,
        session_id = %session.session_id,
        operation_id = %operation_id,
        event_name = "cli.logs.retention",
        removed_files = retention.removed_files,
        removed_bytes = retention.removed_bytes,
        skipped_entries = retention.skipped_entries,
        "CLI log retention completed"
    );

    Some(LogGuard {
        worker: Some(guard),
        marker_file: Some(marker_file),
        active_marker,
        log_path,
        session_id: session.session_id,
    })
}

/// Record the terminal result of a CLI operation using stable searchable fields.
pub fn record_operation_finish(
    operation_id: &crate::observability::OperationId,
    log_guard: Option<&LogGuard>,
    exit_code: u8,
    failed: bool,
) {
    let session_id = log_guard
        .map(LogGuard::session_id)
        .unwrap_or("console-only");
    tracing::debug!(
        schema_version = 1,
        component = "cli",
        process_id = std::process::id(),
        session_id,
        operation_id = %operation_id,
        event_name = "cli.operation.finish",
        outcome = if failed { "failure" } else { "success" },
        exit_code,
        "CLI operation finished"
    );
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
pub fn init_from_env(operation_id: &crate::observability::OperationId) -> Option<LogGuard> {
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

    config.log_dir = apply_log_dir_override(
        config.log_dir,
        std::env::var_os("MORPHIR_LOG_DIR").as_deref(),
    );

    let file_logging = std::env::var("MORPHIR_LOG_FILE").ok();
    config.file_logging = configured_bool(file_logging.as_deref(), config.file_logging);

    init(config, operation_id)
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
    fn file_logging_changes_only_for_explicit_boolean_overrides() {
        assert!(configured_bool(Some("true"), false));
        assert!(configured_bool(Some("1"), false));
        assert!(!configured_bool(Some("false"), true));
        assert!(!configured_bool(Some("0"), true));
        assert!(configured_bool(Some(""), true));
        assert!(configured_bool(Some("invalid"), true));
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
            Some(PathBuf::from("/sandbox/morphir-home/logs/cli"))
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
            Some(PathBuf::from("/managed/logs"))
        );
    }

    #[test]
    fn missing_home_does_not_invent_a_working_directory_log_path() {
        assert_eq!(log_dir_from(None, None), None);
    }

    #[test]
    fn empty_log_directory_override_keeps_the_resolved_default() {
        let default = PathBuf::from("/sandbox/morphir-home/logs/cli");

        assert_eq!(
            apply_log_dir_override(default.clone(), Some(std::ffi::OsStr::new(""))),
            default
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

    #[test]
    fn file_appender_creation_reports_an_unusable_session_path() {
        let temporary = tempfile::tempdir().unwrap();
        let file_name = "session.jsonl";
        std::fs::create_dir(temporary.path().join(file_name)).unwrap();

        assert!(create_file_appender(temporary.path(), file_name).is_err());
    }
}
