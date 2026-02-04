//! Output formatting utilities for programmatic interactions

use serde::{Deserialize, Serialize};
use std::io::{self, Write};

/// Output format options
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    /// Human-readable output
    Human,
    /// Single JSON object
    Json,
    /// JSON Lines (newline-delimited JSON, one object per line)
    JsonLines,
}

impl OutputFormat {
    /// Determine format from CLI flags
    pub fn from_flags(json: bool, json_lines: bool) -> Self {
        if json_lines {
            Self::JsonLines
        } else if json {
            Self::Json
        } else {
            Self::Human
        }
    }
}

/// Write output in the specified format
pub fn write_output<T: Serialize>(format: OutputFormat, value: &T) -> std::io::Result<()> {
    match format {
        OutputFormat::Human => {
            // Human-readable output is handled by command-specific logic
            Ok(())
        }
        OutputFormat::Json => {
            let json = serde_json::to_string_pretty(value)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            println!("{}", json);
            Ok(())
        }
        OutputFormat::JsonLines => {
            let json = serde_json::to_string(value)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            println!("{}", json);
            Ok(())
        }
    }
}

/// Write JSON Lines (streaming) - one object per line
pub fn write_json_lines<T: Serialize>(items: impl Iterator<Item = T>) -> anyhow::Result<()> {
    let stdout = io::stdout();
    let mut handle = stdout.lock();

    for item in items {
        let json = serde_json::to_string(&item)?;
        writeln!(handle, "{}", json)?;
    }

    Ok(())
}

/// Compile command output structure
#[derive(Debug, Serialize)]
pub struct CompileOutput {
    pub success: bool,
    pub ir: Option<serde_json::Value>,
    pub diagnostics: Vec<Diagnostic>,
    pub modules: Vec<String>,
    pub output_path: String,
}

/// Generate command output structure
#[derive(Debug, Serialize)]
pub struct GenerateOutput {
    pub success: bool,
    pub artifacts: Vec<String>,
    pub diagnostics: Vec<Diagnostic>,
    pub output_path: String,
}

/// Diagnostic information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    pub level: String, // "error", "warning", "info"
    pub message: String,
    pub file: Option<String>,
    pub line: Option<u32>,
    pub column: Option<u32>,
}

/// Progress message for streaming output
#[derive(Debug, Serialize)]
pub struct ProgressMessage {
    #[serde(rename = "type")]
    pub message_type: String, // "progress"
    pub message: String,
}

/// Result message for streaming output
#[derive(Debug, Serialize)]
pub struct ResultMessage<T: Serialize> {
    #[serde(rename = "type")]
    pub message_type: String, // "result"
    pub success: bool,
    #[serde(flatten)]
    pub data: T,
}
