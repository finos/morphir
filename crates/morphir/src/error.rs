//! Error handling utilities for CLI commands

use crate::output::{Diagnostic, OutputFormat};
use miette::Diagnostic as MietteDiagnostic;

/// CLI error that can be formatted for human or JSON output
#[derive(Debug, thiserror::Error, MietteDiagnostic)]
pub enum CliError {
    #[error("Configuration error")]
    #[diagnostic(code(cli::config_error))]
    Config {
        #[source]
        error: anyhow::Error,
    },

    #[error("Extension error: {message}")]
    #[diagnostic(code(cli::extension_error))]
    Extension { message: String },

    #[error("Compilation error: {message}")]
    #[diagnostic(code(cli::compilation_error))]
    Compilation { message: String },

    #[error("File system error")]
    #[diagnostic(code(cli::filesystem_error))]
    FileSystem {
        #[source]
        error: std::io::Error,
    },

    #[error("Validation error: {message}")]
    #[diagnostic(code(cli::validation_error))]
    Validation { message: String },
}

impl CliError {
    /// Convert to diagnostic for JSON output
    pub fn to_diagnostic(&self) -> Diagnostic {
        Diagnostic {
            level: "error".to_string(),
            message: self.to_string(),
            file: None,
            line: None,
            column: None,
        }
    }

    /// Report error using miette (for human-readable output)
    pub fn report(&self) {
        // Print error with color using owo_colors if available
        eprintln!("error: {}", self);
    }

    /// Report error based on output format
    pub fn report_with_format(&self, format: OutputFormat) {
        match format {
            OutputFormat::Human => {
                self.report();
            }
            OutputFormat::Json | OutputFormat::JsonLines => {
                let diagnostic = self.to_diagnostic();
                if let Ok(json) = serde_json::to_string_pretty(&diagnostic) {
                    eprintln!("{}", json);
                }
            }
        }
    }
}

impl From<anyhow::Error> for CliError {
    fn from(error: anyhow::Error) -> Self {
        CliError::Config { error }
    }
}

impl From<std::io::Error> for CliError {
    fn from(error: std::io::Error) -> Self {
        CliError::FileSystem { error }
    }
}

/// Helper to convert anyhow errors to CLI errors with format awareness
pub fn handle_error<T>(result: anyhow::Result<T>, format: OutputFormat) -> Result<T, CliError> {
    result.map_err(|e| {
        let cli_err = CliError::Config { error: e };
        cli_err.report_with_format(format);
        cli_err
    })
}

/// Convert extension diagnostics to CLI diagnostics
pub fn convert_extension_diagnostics(
    ext_diagnostics: &[morphir_extension_sdk::Diagnostic],
) -> Vec<Diagnostic> {
    ext_diagnostics
        .iter()
        .map(|d| Diagnostic {
            level: match d.severity {
                morphir_extension_sdk::DiagnosticSeverity::Error => "error",
                morphir_extension_sdk::DiagnosticSeverity::Warning => "warning",
                morphir_extension_sdk::DiagnosticSeverity::Info => "info",
                morphir_extension_sdk::DiagnosticSeverity::Hint => "hint",
            }
            .to_string(),
            message: d.message.clone(),
            file: d.location.as_ref().map(|l| l.file.clone()),
            line: d.location.as_ref().map(|l| l.start_line),
            column: d.location.as_ref().map(|l| l.start_col),
        })
        .collect()
}
