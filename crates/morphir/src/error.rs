//! Error handling utilities for CLI commands

use crate::output::{Diagnostic, OutputFormat};
use miette::Diagnostic as MietteDiagnostic;
use std::path::PathBuf;

/// A provider-neutral workspace discovery failure retained at host boundaries.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspaceDiscoveryError {
    /// Stable machine-readable failure code.
    pub code: String,
    /// Human-readable failure explanation.
    pub message: String,
    /// Root-confined path associated with the failure, when available.
    pub path: Option<morphir_workspace::RelativePath>,
}

impl std::fmt::Display for WorkspaceDiscoveryError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)?;
        if let Some(path) = &self.path {
            write!(formatter, " at `{}`", path.as_str())?;
        }
        Ok(())
    }
}

impl std::error::Error for WorkspaceDiscoveryError {}

impl From<morphir_workspace::DiscoveryFailure> for WorkspaceDiscoveryError {
    fn from(failure: morphir_workspace::DiscoveryFailure) -> Self {
        Self {
            code: failure.code,
            message: failure.message,
            path: failure.path,
        }
    }
}

/// CLI error that can be formatted for human or JSON output
#[derive(Debug, thiserror::Error, MietteDiagnostic)]
pub enum CliError {
    #[error("Configuration error")]
    #[diagnostic(code(cli::config_error))]
    Config {
        #[source]
        error: anyhow::Error,
    },

    #[error("{error}")]
    #[diagnostic(code(cli::workspace_discovery_error))]
    WorkspaceDiscovery {
        #[source]
        error: WorkspaceDiscoveryError,
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

    /// A copy step's own failure, naming the source and destination it was
    /// copying between. `install` (see `crate::commands::install`) raises
    /// this instead of a bare [`CliError::FileSystem`] for a failed
    /// `std::fs::copy`, so the message a user sees says which file could not
    /// be copied where, rather than just "File system error" with the
    /// underlying `io::Error` as its only detail.
    #[error("install's copy step failed: could not copy '{from}' to '{to}': {error}")]
    #[diagnostic(code(cli::install_copy_error))]
    Copy {
        from: PathBuf,
        to: PathBuf,
        #[source]
        error: std::io::Error,
    },

    #[error("Artifact publication error: {message}")]
    #[diagnostic(code(cli::artifact_publication_error))]
    ArtifactPublication {
        message: String,
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
            code: None,
            related: Vec::new(),
            file: None,
            line: None,
            column: None,
            uri: None,
            range: None,
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
            code: d.code.clone(),
            related: d.related.clone(),
            file: d.location.as_ref().map(|location| location.uri.clone()),
            line: d
                .location
                .as_ref()
                .map(|location| location.range.start.line),
            column: d
                .location
                .as_ref()
                .map(|location| location.range.start.character),
            uri: d.location.as_ref().map(|location| location.uri.clone()),
            range: d.location.as_ref().map(|location| location.range.clone()),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::{
        DiagnosticSeverity, RelatedInformation, SourceLocation, SourcePosition, SourceRange,
    };

    #[test]
    fn extension_diagnostics_preserve_uri_and_zero_based_start_position() {
        let diagnostics = convert_extension_diagnostics(&[morphir_extension_sdk::Diagnostic {
            severity: DiagnosticSeverity::Warning,
            code: Some("TEST".to_owned()),
            message: "example warning".to_owned(),
            location: Some(SourceLocation {
                uri: "file:///workspace/main.gleam".to_owned(),
                range: SourceRange {
                    start: SourcePosition {
                        line: 4,
                        character: 7,
                    },
                    end: SourcePosition {
                        line: 4,
                        character: 8,
                    },
                },
            }),
            related: Vec::new(),
        }]);

        assert_eq!(
            diagnostics[0].file.as_deref(),
            Some("file:///workspace/main.gleam")
        );
        assert_eq!(diagnostics[0].line, Some(4));
        assert_eq!(diagnostics[0].column, Some(7));
    }

    #[test]
    fn mep_diagnostic_conversion_preserves_code_range_and_related_information() {
        let diagnostic = morphir_extension_sdk::Diagnostic {
            severity: DiagnosticSeverity::Error,
            code: Some("elm.type-mismatch".into()),
            message: "Type mismatch".into(),
            location: Some(location("file:///work/Example.elm", 2, 4, 2, 8)),
            related: vec![RelatedInformation {
                location: location("file:///work/Other.elm", 0, 1, 0, 3),
                message: "Expected type declared here".into(),
            }],
        };

        let converted = convert_extension_diagnostics(&[diagnostic]);
        let converted = &converted[0];

        assert_eq!(converted.code.as_deref(), Some("elm.type-mismatch"));
        assert_eq!(converted.uri.as_deref(), Some("file:///work/Example.elm"));
        assert_eq!(converted.range.as_ref().unwrap().start.line, 2);
        assert_eq!(converted.range.as_ref().unwrap().start.character, 4);
        assert_eq!(converted.related.len(), 1);
        assert_eq!(converted.related[0].message, "Expected type declared here");
        assert_eq!(converted.file.as_deref(), Some("file:///work/Example.elm"));
        assert_eq!(converted.line, Some(2));
        assert_eq!(converted.column, Some(4));
    }

    #[test]
    fn legacy_diagnostic_locations_round_trip_without_new_fields() {
        let value = serde_json::json!({
            "level": "warning",
            "message": "Legacy warning",
            "file": "src/Example.elm",
            "line": 7,
            "column": 11
        });

        let diagnostic: Diagnostic = serde_json::from_value(value.clone()).unwrap();

        assert_eq!(diagnostic.file.as_deref(), Some("src/Example.elm"));
        assert_eq!(diagnostic.line, Some(7));
        assert_eq!(diagnostic.column, Some(11));
        assert!(diagnostic.code.is_none());
        assert!(diagnostic.uri.is_none());
        assert!(diagnostic.range.is_none());
        assert!(diagnostic.related.is_empty());
        assert_eq!(serde_json::to_value(diagnostic).unwrap(), value);
    }

    fn location(
        uri: &str,
        start_line: u32,
        start_character: u32,
        end_line: u32,
        end_character: u32,
    ) -> SourceLocation {
        SourceLocation {
            uri: uri.into(),
            range: SourceRange {
                start: SourcePosition {
                    line: start_line,
                    character: start_character,
                },
                end: SourcePosition {
                    line: end_line,
                    character: end_character,
                },
            },
        }
    }
}
