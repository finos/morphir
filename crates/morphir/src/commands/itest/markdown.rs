//! Markdown authoring adapter for the shared scenario and workspace validators.
use crate::notebook::Notebook;
use anyhow::{Context, Result, bail, ensure};
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use serde_json::{Map, Value, json};
use std::{
    collections::{HashMap, HashSet},
    ops::Range,
};

enum Block {
    Scenario {
        title: String,
        id: Option<String>,
        /// The byte offset of the heading's first character in the frontmatter-stripped body.
        start: usize,
    },
    Fence {
        info: String,
        range: Range<usize>,
        top_level: bool,
    },
}

#[derive(Clone, Copy)]
enum Role {
    Command,
    Assertion,
    Golden,
    File,
}

impl Role {
    fn from_info(info: &str) -> Result<Option<Self>> {
        let words: Vec<_> = info.split_whitespace().collect();
        if !words.iter().any(|word| word.starts_with("morphir:")) {
            return Ok(None);
        }
        ensure!(
            words.len() == 2 && words[0] == "yaml",
            "Morphir metadata fence must be 'yaml morphir:<role>'"
        );
        Ok(Some(match words[1] {
            "morphir:command" => Self::Command,
            "morphir:assertion" => Self::Assertion,
            "morphir:golden" => Self::Golden,
            "morphir:file" => Self::File,
            other => bail!("unknown Morphir fence {other:?}"),
        }))
    }
}

struct Section {
    id: String,
    title: String,
    /// The heading's 1-based line in the source document (including its frontmatter).
    line: usize,
    /// Each cell's own `yaml morphir:<role>` metadata fence line, keyed by the cell's id.
    fence_lines: HashMap<String, usize>,
    cells: Vec<Value>,
}

/// One `##` section of a `scenarios.md` file, lowered to a synthetic notebook: its resolved id,
/// its heading title, the heading's 1-based line in the source file, each cell's own metadata
/// fence line, and the notebook `model::parse` reads.
pub(super) struct ParsedSection {
    /// The section's id: explicit (`{#id}`) or derived from its title.
    pub(super) id: String,
    /// The section heading's text.
    pub(super) title: String,
    /// The section heading's 1-based line in the source `scenarios.md` file.
    pub(super) line: usize,
    /// Each cell's own `yaml morphir:<role>` metadata fence line, keyed by the cell's id. A
    /// command, assertion or golden fence's line, for a reader that wants to point a failure at
    /// its own fence rather than at the section heading.
    pub(super) fence_lines: HashMap<String, usize>,
    /// The section's synthetic notebook, as `model::parse` expects it.
    pub(super) notebook: Notebook,
}

/// A `scenarios.md` file's frontmatter metadata and its `##` sections, in source order.
pub(super) struct ParsedDocument {
    /// The frontmatter's own metadata: its title (not a section heading's), description, tags,
    /// provider and workspace.
    pub(super) metadata: super::model::Metadata,
    /// The document's sections, in source order.
    pub(super) sections: Vec<ParsedSection>,
}

/// Heading IDs are usable as the fragment of an itest path filter.
pub(super) fn validate_id(id: &str) -> Result<()> {
    ensure!(
        !id.is_empty()
            && id.len() <= 64
            && id
                .bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"-_".contains(&c)),
        "invalid Markdown scenario id {id:?}; use 1..64 lowercase ASCII letters, digits, hyphens or underscores"
    );
    Ok(())
}

/// A section's id: `explicit` when given, or else the title's lowercase ASCII words joined by
/// hyphens.
pub(super) fn section_id(title: &str, explicit: Option<String>) -> Result<String> {
    let id = explicit.unwrap_or_else(|| {
        title
            .to_ascii_lowercase()
            .split(|c: char| !c.is_ascii_alphanumeric())
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("-")
    });
    validate_id(&id)?;
    Ok(id)
}

fn yaml(text: &str) -> Result<Map<String, Value>> {
    serde_saphyr::from_str(text).context("invalid YAML metadata")
}

fn frontmatter(text: &str) -> Result<(super::model::Metadata, Map<String, Value>, &str)> {
    let mut lines = text.split_inclusive('\n');
    let first = lines.next().context("missing YAML frontmatter")?;
    ensure!(
        first.trim_end_matches(['\r', '\n']) == "---",
        "scenario document must start with YAML frontmatter"
    );
    let mut end = first.len();
    for line in lines {
        if line.trim_end_matches(['\r', '\n']) == "---" {
            let mut metadata = yaml(&text[first.len()..end])?;
            ensure!(
                metadata.remove("version") == Some(json!(1)),
                "expected Markdown scenario version 1"
            );
            // Validate defaults even when every heading later supplies its own title.
            let context: super::model::Metadata =
                serde_json::from_value(Value::Object(metadata.clone()))
                    .context("invalid scenario frontmatter")?;
            ensure!(
                !context.title.trim().is_empty(),
                "frontmatter needs a title"
            );
            return Ok((context, metadata, &text[end + line.len()..]));
        }
        end += line.len();
    }
    bail!("unclosed YAML frontmatter")
}

fn blocks(text: &str) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut depth = 0;
    let mut heading: Option<(String, Option<String>, usize)> = None;
    for (event, range) in
        Parser::new_ext(text, Options::ENABLE_HEADING_ATTRIBUTES).into_offset_iter()
    {
        match event {
            Event::Start(tag) => {
                match tag {
                    Tag::Heading {
                        level: HeadingLevel::H2,
                        id,
                        ..
                    } if depth == 0 => {
                        heading = Some((String::new(), id.map(|id| id.into_string()), range.start));
                    }
                    Tag::CodeBlock(CodeBlockKind::Fenced(info)) => blocks.push(Block::Fence {
                        info: info.into_string(),
                        range,
                        top_level: depth == 0,
                    }),
                    _ => {}
                }
                depth += 1;
            }
            Event::End(tag) => {
                depth -= 1;
                if tag == TagEnd::Heading(HeadingLevel::H2)
                    && let Some((title, id, start)) = heading.take()
                {
                    blocks.push(Block::Scenario { title, id, start });
                }
            }
            Event::Text(text) | Event::Code(text) => {
                if let Some((title, _, _)) = &mut heading {
                    title.push_str(&text);
                }
            }
            Event::SoftBreak | Event::HardBreak => {
                if let Some((title, _, _)) = &mut heading {
                    title.push(' ');
                }
            }
            _ => {}
        }
    }
    blocks
}

/// Read source bytes rather than rendered Markdown text, retaining CRLF and indentation.
fn fenced_source<'a>(text: &'a str, range: &Range<usize>) -> Result<&'a str> {
    ensure!(
        range.start == 0 || text.as_bytes()[range.start - 1] == b'\n',
        "Morphir fences must start at column one"
    );
    let raw = &text[range.clone()];
    let (opening, remainder) = raw
        .split_once('\n')
        .context("unclosed Morphir code fence")?;
    let marker = opening.as_bytes()[0];
    let count = opening.bytes().take_while(|c| *c == marker).count();
    let tail = remainder.trim_end_matches(['\r', '\n']);
    let close = tail.rfind('\n').map_or(0, |position| position + 1);
    let closing_line = &tail[close..];
    let indentation = closing_line.bytes().take_while(|c| *c == b' ').count();
    let closing = closing_line[indentation..].trim_end_matches([' ', '\t', '\r']);
    ensure!(
        indentation <= 3
            && count >= 3
            && closing.len() >= count
            && closing.bytes().all(|c| c == marker),
        "unclosed Morphir code fence"
    );
    Ok(&remainder[..close])
}

fn cell(role: Role, mut metadata: Map<String, Value>, info: &str, source: &str) -> Result<Value> {
    let id = metadata.remove("id").context("Morphir block needs an id")?;
    ensure!(id.is_string(), "Morphir block id must be a string");
    let language = info
        .split_whitespace()
        .next()
        .context("Morphir source fence needs a source language")?;
    ensure!(
        !metadata.contains_key("kind"),
        "block kind comes from the metadata fence marker"
    );
    let profile = match role {
        Role::File => {
            ensure!(
                !metadata.contains_key("language"),
                "file language comes from the source fence"
            );
            metadata.insert("language".into(), json!(language));
            json!({"file": metadata})
        }
        Role::Golden => {
            metadata.insert("kind".into(), json!("golden"));
            json!({"itest":metadata})
        }
        Role::Command | Role::Assertion => {
            let kind = if matches!(role, Role::Command) {
                "command"
            } else {
                ensure!(language == "rego", "assertion source language must be rego");
                "assertion"
            };
            metadata.insert("kind".into(), json!(kind));
            json!({"itest": metadata})
        }
    };
    Ok(json!({"id": id, "cell_type": "code", "source": source,
        "metadata": {"morphir": profile}, "outputs": [], "execution_count": null}))
}

/// Parses a `scenarios.md` file into its frontmatter metadata and its `##` sections. This is the
/// single Markdown pass: [`parse`] and [`super::reader::read_scenarios_md`] both build on it, so
/// the file is never parsed twice.
pub(super) fn parse_sections(text: &str) -> Result<ParsedDocument> {
    let (frontmatter_metadata, defaults, body) = frontmatter(text)?;
    let body_offset = text.len() - body.len();
    let prefix_lines = text[..body_offset].bytes().filter(|c| *c == b'\n').count();
    let mut sections: Vec<Section> = Vec::new();
    let mut ids = HashSet::new();
    let mut pending = None;
    for block in blocks(body) {
        match block {
            Block::Scenario { title, id, start } => {
                ensure!(
                    pending.is_none(),
                    "metadata needs a source fence before the next scenario heading"
                );
                ensure!(!title.trim().is_empty(), "scenario heading needs a title");
                let id = section_id(&title, id)?;
                ensure!(ids.insert(id.clone()), "duplicate scenario id {id:?}");
                let line = prefix_lines + body[..start].bytes().filter(|c| *c == b'\n').count() + 1;
                sections.push(Section {
                    id,
                    title,
                    line,
                    fence_lines: HashMap::new(),
                    cells: Vec::new(),
                });
            }
            Block::Fence {
                info,
                range,
                top_level,
            } => {
                let line = body[..range.start].bytes().filter(|c| *c == b'\n').count() + 1;
                let absolute_line = prefix_lines + line;
                let role =
                    Role::from_info(&info).with_context(|| format!("Markdown body line {line}"))?;
                if role.is_none() && pending.is_none() {
                    continue;
                }
                ensure!(
                    top_level,
                    "Morphir metadata and source fences must be top-level (body line {line})"
                );
                let source = fenced_source(body, &range)
                    .with_context(|| format!("Markdown body line {line}"))?;
                if let Some(role) = role {
                    ensure!(
                        !sections.is_empty(),
                        "Morphir block needs a preceding level-two scenario heading"
                    );
                    ensure!(
                        pending.is_none(),
                        "metadata needs a source fence before another metadata fence"
                    );
                    let metadata =
                        yaml(source).with_context(|| format!("Markdown body line {line}"))?;
                    if let Some(id) = metadata.get("id").and_then(Value::as_str) {
                        sections
                            .last_mut()
                            .unwrap()
                            .fence_lines
                            .insert(id.to_owned(), absolute_line);
                    }
                    if matches!(role, Role::Golden) && metadata.contains_key("expected_file") {
                        // A disk expectation has no inline source fence.
                        let cell = cell(role, metadata, "text", "")
                            .with_context(|| format!("Markdown body line {line}"))?;
                        sections.last_mut().unwrap().cells.push(cell);
                    } else {
                        pending = Some((role, metadata));
                    }
                } else if let Some((role, metadata)) = pending.take() {
                    let cell = cell(role, metadata, &info, source)
                        .with_context(|| format!("Markdown body line {line}"))?;
                    sections.last_mut().unwrap().cells.push(cell);
                }
            }
        }
    }
    ensure!(pending.is_none(), "metadata needs a following source fence");
    ensure!(
        !sections.is_empty(),
        "Markdown document needs at least one level-two scenario heading"
    );
    let sections = sections
        .into_iter()
        .map(|section| {
            let mut metadata = defaults.clone();
            metadata.insert("title".into(), json!(section.title));
            let document = json!({"nbformat": 4, "nbformat_minor": 5,
            "metadata": {"morphir": {"version": 1, "itest": metadata}}, "cells": section.cells});
            let notebook = Notebook::parse(&document.to_string())
                .with_context(|| format!("Markdown scenario {}", section.id))?;
            Ok(ParsedSection {
                id: section.id,
                title: section.title,
                line: section.line,
                fence_lines: section.fence_lines,
                notebook,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(ParsedDocument {
        metadata: frontmatter_metadata,
        sections,
    })
}

/// Reads every `##` section of a `scenarios.md` file into a synthetic notebook, keyed by its
/// section id. [`super::reader::read_scenarios_md`] lowers the same sections into Gherkin
/// scenarios by calling [`parse_sections`] directly, so this file is parsed only once. Only the
/// legacy loader of the unit tests uses this.
#[cfg(test)]
pub(super) fn parse(text: &str) -> Result<Vec<(String, Notebook)>> {
    Ok(parse_sections(text)?
        .sections
        .into_iter()
        .map(|section| (section.id, section.notebook))
        .collect())
}
