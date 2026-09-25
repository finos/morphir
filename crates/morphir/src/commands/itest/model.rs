//! The scenario model of a `scenarios.md` section: its metadata, and its commands with their
//! assertions and golden checks, checked before anything runs.
use super::golden::{LineEndings, Selection};
use super::markdown::{CellRole, ParsedSection};
use anyhow::{Context, Result, ensure};
use morphir_evaluator::ProviderId;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Metadata {
    pub title: String,
    pub description: String,
    pub tags: Vec<String>,
    pub provider: ProviderId,
    #[serde(default)]
    pub workspace: Workspace,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Workspace {
    Directory {
        path: String,
        #[serde(default)]
        exclude: Vec<String>,
    },
    /// Only the scenario's own `morphir:file` blocks (or `yaml itest` files); no disk inputs.
    Inline {},
}

impl Default for Workspace {
    fn default() -> Self {
        Self::Directory {
            path: ".".into(),
            exclude: Vec::new(),
        }
    }
}

impl Workspace {
    /// A directory workspace's path and exclusions must be portable relative paths.
    pub fn validate(&self) -> Result<()> {
        if let Workspace::Directory { path, exclude } = self {
            if path != "." {
                relative_path(path).context("invalid workspace directory")?;
            }
            for path in exclude {
                relative_path(path).context("invalid workspace exclusion")?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Capture {
    pub name: String,
    pub path: String,
    pub format: CaptureFormat,
}
#[derive(Debug, Deserialize, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum CaptureFormat {
    Json,
    Text,
    Exists,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Role {
    Command {
        name: String,
        timeout_seconds: u64,
        #[serde(default)]
        captures: Vec<Capture>,
        #[serde(default)]
        stdout_json: bool,
    },
    Assertion {
        command: String,
        entrypoints: Vec<String>,
    },
    Golden {
        command: String,
        actual: String,
        #[serde(default, deserialize_with = "expected_file")]
        expected_file: Option<String>,
        #[serde(default)]
        select: Selection,
        #[serde(default)]
        line_endings: LineEndings,
    },
}

// Omission selects inline text; an explicit null is an invalid file reference.
fn expected_file<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<String>, D::Error> {
    String::deserialize(deserializer).map(Some)
}

#[derive(Debug)]
pub struct Assertion {
    pub id: String,
    pub kind: AssertionKind,
}

#[derive(Debug)]
pub enum AssertionKind {
    Rego {
        source: String,
        entrypoints: Vec<String>,
    },
    Golden(Golden),
}

#[derive(Debug)]
pub enum ExpectedText {
    Inline(String),
    File(String),
}

#[derive(Debug)]
pub struct Golden {
    pub actual: String,
    pub expected: ExpectedText,
    pub select: Selection,
    pub line_endings: LineEndings,
}
#[derive(Debug)]
pub struct Step {
    pub id: String,
    pub args: Vec<String>,
    pub timeout_seconds: u64,
    pub stdout_json: bool,
    pub captures: Vec<Capture>,
    pub assertions: Vec<Assertion>,
}

/// Reads a section's scenario metadata and its steps, and checks them: the metadata's title,
/// description and tags, each command's literal `morphir` command line, timeout and captures, and
/// that each assertion and golden check names an earlier command.
pub fn parse(section: &ParsedSection) -> Result<(Metadata, Vec<Step>)> {
    let metadata: Metadata = serde_json::from_value(Value::Object(section.metadata.clone()))
        .context("invalid scenario metadata")?;
    metadata.workspace.validate()?;
    ensure!(
        !metadata.title.trim().is_empty() && !metadata.description.trim().is_empty(),
        "scenario needs title and description"
    );
    ensure!(!metadata.tags.is_empty(), "scenario needs tags");
    let mut tags = HashSet::new();
    for tag in &metadata.tags {
        ensure!(
            !tag.is_empty()
                && tag
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b":-._".contains(&c)),
            "invalid tag {tag:?}"
        );
        ensure!(tags.insert(tag), "duplicate tag {tag:?}");
    }
    let mut steps: Vec<Step> = Vec::new();
    let mut names = HashSet::new();
    for cell in &section.cells {
        if cell.role == CellRole::File {
            continue;
        }
        let role: Role = serde_json::from_value(Value::Object(cell.metadata.clone()))
            .with_context(|| format!("cell {}: invalid itest role", cell.id))?;
        match role {
            Role::Command {
                name,
                timeout_seconds,
                captures,
                stdout_json,
            } => {
                ensure!(
                    !name.trim().is_empty() && names.insert(name.clone()),
                    "command names must be nonempty and unique"
                );
                ensure!(
                    (1..=300).contains(&timeout_seconds),
                    "command timeout must be 1..300 seconds"
                );
                let arguments = shell_words::split(&cell.source)
                    .context("invalid literal CLI command quoting")?;
                ensure!(
                    arguments.first().map(String::as_str) == Some("morphir") && arguments.len() > 1,
                    "cell {} must contain one literal morphir command",
                    cell.id
                );
                let mut capture_names = HashSet::new();
                for capture in &captures {
                    ensure!(
                        !capture.name.is_empty() && capture_names.insert(&capture.name),
                        "capture names must be nonempty and unique"
                    );
                    relative_path(&capture.path)?;
                }
                steps.push(Step {
                    id: cell.id.clone(),
                    args: arguments[1..].to_vec(),
                    timeout_seconds,
                    stdout_json,
                    captures,
                    assertions: Vec::new(),
                });
            }
            Role::Golden {
                command,
                actual,
                expected_file,
                select,
                line_endings,
            } => {
                relative_path(&actual).context("invalid golden actual path")?;
                select.validate()?;
                let expected = match expected_file {
                    Some(path) => {
                        relative_path(&path).context("invalid golden expected path")?;
                        ensure!(
                            cell.source.is_empty(),
                            "golden {} cannot combine expected_file and inline source",
                            cell.id
                        );
                        ExpectedText::File(path)
                    }
                    None => ExpectedText::Inline(cell.source.clone()),
                };
                let step = steps
                    .iter_mut()
                    .find(|step| step.id == command)
                    .with_context(|| {
                        format!(
                            "golden {} references missing or forward command {command:?}",
                            cell.id
                        )
                    })?;
                step.assertions.push(Assertion {
                    id: cell.id.clone(),
                    kind: AssertionKind::Golden(Golden {
                        actual,
                        expected,
                        select,
                        line_endings,
                    }),
                });
            }
            Role::Assertion {
                command,
                entrypoints,
            } => {
                let step = steps
                    .iter_mut()
                    .find(|step| step.id == command)
                    .with_context(|| {
                        format!(
                            "assertion {} references missing or forward command {command:?}",
                            cell.id
                        )
                    })?;
                ensure!(
                    !entrypoints.is_empty(),
                    "assertion {} needs entrypoints",
                    cell.id
                );
                let mut unique = HashSet::new();
                for rule in &entrypoints {
                    ensure!(
                        rule.starts_with("data.") && unique.insert(rule),
                        "assertion {}: entrypoints must be unique named data rules",
                        cell.id
                    );
                }
                ensure!(
                    !cell.source.trim().is_empty(),
                    "assertion {} is empty",
                    cell.id
                );
                step.assertions.push(Assertion {
                    id: cell.id.clone(),
                    kind: AssertionKind::Rego {
                        source: cell.source.clone(),
                        entrypoints,
                    },
                });
            }
        }
    }
    ensure!(!steps.is_empty(), "scenario has no CLI commands");
    for step in &steps {
        ensure!(
            !step.assertions.is_empty(),
            "command {} has no assertions",
            step.id
        );
    }
    Ok((metadata, steps))
}

/// Checks that `value` is a normalized, portable path that stays inside the workspace: relative,
/// with `/` separators, no `.` or `..` component, and no component that Windows refuses.
pub fn relative_path(value: &str) -> Result<()> {
    ensure!(
        !value.is_empty() && !value.contains(['\\', ':']),
        "expected a portable relative path: {value:?}"
    );
    ensure!(
        value
            .split('/')
            .all(|part| !part.is_empty() && part != "." && part != ".."),
        "path escapes the workspace or is not normalized: {value:?}"
    );
    for part in value.split('/') {
        ensure!(
            !part.ends_with(['.', ' '])
                && !part
                    .chars()
                    .any(|ch| ch.is_control() || "<>\"|?*".contains(ch)),
            "nonportable path component: {part:?}"
        );
        let stem = part
            .split('.')
            .next()
            .unwrap_or_default()
            .to_ascii_uppercase();
        let device = matches!(
            stem.as_str(),
            "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
        ) || ["COM", "LPT"].iter().any(|prefix| {
            stem.strip_prefix(prefix).is_some_and(|suffix| {
                matches!(
                    suffix,
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
                )
            })
        });
        ensure!(!device, "reserved device name in workspace path: {part:?}");
    }
    Ok(())
}
