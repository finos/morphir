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
    /// Absolute install target when `-o` was given.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installed_path: Option<String>,
}

/// Generate command output structure
#[derive(Debug, Serialize)]
pub struct GenerateOutput {
    pub success: bool,
    pub artifacts: Vec<String>,
    pub diagnostics: Vec<Diagnostic>,
    pub output_path: String,
    /// Absolute install target when `-o` was given.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installed_path: Option<String>,
}

/// Write a human-readable generation result to the appropriate standard stream.
pub fn write_generate_human(output: &GenerateOutput) -> io::Result<()> {
    if output.success {
        let stdout = io::stdout();
        let mut writer = stdout.lock();
        writeln!(writer, "Code generation successful!")?;
        writeln!(writer, "Output: {}", output.output_path)?;
        if let Some(installed) = &output.installed_path {
            writeln!(writer, "Installed: {installed}")?;
        }
        if !output.artifacts.is_empty() {
            writeln!(writer, "Artifacts:")?;
            for artifact in &output.artifacts {
                writeln!(writer, "  {artifact}")?;
            }
        }
        write_human_diagnostics(&mut writer, &output.diagnostics)
    } else {
        let stderr = io::stderr();
        write_human_diagnostics(&mut stderr.lock(), &output.diagnostics)
    }
}

fn write_human_diagnostics(writer: &mut impl Write, diagnostics: &[Diagnostic]) -> io::Result<()> {
    if diagnostics.is_empty() {
        return Ok(());
    }
    writeln!(writer, "Diagnostics:")?;
    for diagnostic in diagnostics {
        match &diagnostic.code {
            Some(code) => writeln!(
                writer,
                "  {}[{code}]: {}",
                diagnostic.level, diagnostic.message
            )?,
            None => writeln!(writer, "  {}: {}", diagnostic.level, diagnostic.message)?,
        }
    }
    Ok(())
}

/// Diagnostic information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    pub level: String, // "error", "warning", "info"
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub related: Vec<morphir_extension_sdk::RelatedInformation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub line: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub column: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub uri: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub range: Option<morphir_extension_sdk::SourceRange>,
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
