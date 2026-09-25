use super::golden::{LineEndings, Selection};
pub use crate::notebook::relative_path;
use crate::notebook::{CellKind, Notebook};
use anyhow::{Context, Result, ensure};
use morphir_evaluator::ProviderId;
use serde::Deserialize;
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
    #[serde(alias = "inline")]
    Notebook {},
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
    pub name: String,
    pub args: Vec<String>,
    pub timeout_seconds: u64,
    pub stdout_json: bool,
    pub captures: Vec<Capture>,
    pub assertions: Vec<Assertion>,
}

pub fn parse(notebook: &Notebook) -> Result<(Metadata, Vec<Step>)> {
    let profile = &notebook.document()["metadata"]["morphir"];
    ensure!(
        profile["version"] == 1,
        "missing Morphir notebook profile version 1"
    );
    let metadata: Metadata =
        serde_json::from_value(profile["itest"].clone()).context("invalid scenario metadata")?;
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
    for cell in notebook.cells() {
        let Some(role) = cell.morphir().get("itest") else {
            continue;
        };
        ensure!(
            cell.kind() == CellKind::Code,
            "cell {}: executable role requires code cell",
            cell.id()
        );
        ensure!(
            cell.morphir().get("file").is_none(),
            "cell {} cannot be both workspace file and executable",
            cell.id()
        );
        let role: Role = serde_json::from_value(role.clone())
            .with_context(|| format!("cell {}: invalid itest role", cell.id()))?;
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
                let arguments = shell_words::split(cell.source())
                    .context("invalid literal CLI command quoting")?;
                ensure!(
                    arguments.first().map(String::as_str) == Some("morphir") && arguments.len() > 1,
                    "cell {} must contain one literal morphir command",
                    cell.id()
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
                    id: cell.id().to_owned(),
                    name,
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
                            cell.source().is_empty(),
                            "golden {} cannot combine expected_file and inline source",
                            cell.id()
                        );
                        ExpectedText::File(path)
                    }
                    None => ExpectedText::Inline(cell.source().to_owned()),
                };
                let step = steps
                    .iter_mut()
                    .find(|step| step.id == command)
                    .with_context(|| {
                        format!(
                            "golden {} references missing or forward command {command:?}",
                            cell.id()
                        )
                    })?;
                step.assertions.push(Assertion {
                    id: cell.id().to_owned(),
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
                            cell.id()
                        )
                    })?;
                ensure!(
                    !entrypoints.is_empty(),
                    "assertion {} needs entrypoints",
                    cell.id()
                );
                let mut unique = HashSet::new();
                for rule in &entrypoints {
                    ensure!(
                        rule.starts_with("data.") && unique.insert(rule),
                        "assertion {}: entrypoints must be unique named data rules",
                        cell.id()
                    );
                }
                ensure!(
                    !cell.source().trim().is_empty(),
                    "assertion {} is empty",
                    cell.id()
                );
                step.assertions.push(Assertion {
                    id: cell.id().to_owned(),
                    kind: AssertionKind::Rego {
                        source: cell.source().to_owned(),
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
