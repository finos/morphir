//! Structured logging infrastructure for Morphir CLI.
//!
//! This module provides logging configuration that adheres to the logging standards:
//! - Console logs go to stderr (stdout is reserved for program output)
//! - File logs go to `.morphir/logs/` (workspace) or `~/.morphir/logs/` (global)
//! - Structured JSON format for file logs
//! - Configurable via environment variables and morphir.toml
//!
//! # Usage
//!
//! ```ignore
//! // Initialize with defaults (console to stderr, no file logging)
//! let _guard = logging::init_default();
//!
//! // Or initialize from environment variables
//! let _guard = logging::init_from_env();
//! ```

// Allow dead code while the logging infrastructure is scaffolded but not yet integrated
#![allow(dead_code)]

use std::path::PathBuf;
use tracing::Level;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{
    EnvFilter, Layer,
    fmt::{self, format::FmtSpan},
    layer::SubscriberExt,
    util::SubscriberInitExt,
};

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
            file_logging: false, // Disabled by default for CLI
            json_file_logs: true,
        }
    }
}

/// Determine the default log directory.
///
/// Priority:
/// 1. MORPHIR_LOG_DIR environment variable
/// 2. `.morphir/logs/` in current or parent directory (workspace)
/// 3. `~/.morphir/logs/` (global fallback)
fn default_log_dir() -> PathBuf {
    // Check environment variable
    if let Ok(dir) = std::env::var("MORPHIR_LOG_DIR") {
        return PathBuf::from(dir);
    }

    // Check for workspace-local .morphir directory
    if let Some(workspace_dir) = find_workspace_root() {
        return workspace_dir.join(".morphir").join("logs");
    }

    // Global fallback
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".morphir")
        .join("logs")
}

/// Find the workspace root by looking for morphir.toml or .morphir directory.
fn find_workspace_root() -> Option<PathBuf> {
    let mut current = std::env::current_dir().ok()?;

    loop {
        // Check for morphir.toml
        if current.join("morphir.toml").exists() {
            return Some(current);
        }

        // Check for .morphir directory
        if current.join(".morphir").is_dir() {
            return Some(current);
        }

        // Move to parent directory
        if !current.pop() {
            break;
        }
    }

    None
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

/// Initialize the logging system with the given configuration.
///
/// Returns a guard that must be kept alive for the duration of the program
/// to ensure file logs are flushed.
pub fn init(config: LogConfig) -> Option<WorkerGuard> {
    // Build the console layer (writes to stderr)
    let console_layer = fmt::layer()
        .with_target(false)
        .with_writer(std::io::stderr)
        .with_ansi(true)
        .compact();

    // Build the filter
    let env_filter = std::env::var("MORPHIR_LOG_LEVEL")
        .ok()
        .map(|level| parse_log_level(&level))
        .unwrap_or(config.console_level);

    let filter = EnvFilter::new(format!("morphir={}", env_filter));

    // Initialize with just console layer by default
    if !config.file_logging {
        tracing_subscriber::registry()
            .with(filter)
            .with(console_layer)
            .init();
        return None;
    }

    // Create log directory if needed
    if let Err(e) = std::fs::create_dir_all(&config.log_dir) {
        eprintln!("Warning: Failed to create log directory: {}", e);
        tracing_subscriber::registry()
            .with(filter)
            .with(console_layer)
            .init();
        return None;
    }

    // Set up file appender with rotation
    let file_appender = tracing_appender::rolling::daily(&config.log_dir, "morphir.log");
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    // Build the file layer
    let file_layer = if config.json_file_logs {
        fmt::layer()
            .with_target(true)
            .with_writer(non_blocking)
            .with_ansi(false)
            .with_span_events(FmtSpan::CLOSE)
            .json()
            .boxed()
    } else {
        fmt::layer()
            .with_target(true)
            .with_writer(non_blocking)
            .with_ansi(false)
            .with_span_events(FmtSpan::CLOSE)
            .boxed()
    };

    tracing_subscriber::registry()
        .with(filter)
        .with(console_layer)
        .with(file_layer)
        .init();

    Some(guard)
}

/// Initialize logging with default configuration.
///
/// This is a convenience function for the common case where you want
/// console logging to stderr with sensible defaults.
pub fn init_default() -> Option<WorkerGuard> {
    init(LogConfig::default())
}

/// Initialize logging from environment variables.
///
/// Respects:
/// - MORPHIR_LOG_LEVEL: Console log level (trace, debug, info, warn, error)
/// - MORPHIR_LOG_DIR: Directory for log files
/// - MORPHIR_LOG_FILE: Enable file logging (true/false)
pub fn init_from_env() -> Option<WorkerGuard> {
    let mut config = LogConfig::default();

    if let Ok(level) = std::env::var("MORPHIR_LOG_LEVEL") {
        config.console_level = parse_log_level(&level);
    }

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
}
