//! The `scenarios.md` authoring format: YAML frontmatter, then one scenario for each `##`
//! section, each made of Morphir blocks (a `yaml morphir:<role>` metadata fence and the source
//! fence after it).
use anyhow::{Context, Result, bail, ensure};
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use serde::Deserialize;
use serde_json::{Map, Value, json};
use std::{collections::HashSet, ops::Range};

/// A `##` heading or a fence of the frontmatter-stripped body, in source order.
enum Item {
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

/// What a Morphir block is, from the marker of its `yaml morphir:<role>` metadata fence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum CellRole {
    /// `morphir:command`: one literal `morphir` command line.
    Command,
    /// `morphir:assertion`: a Rego policy over the last command's observation.
    Assertion,
    /// `morphir:golden`: an expected text for a file the last command wrote.
    Golden,
    /// `morphir:file`: a file written into the workspace before the commands run.
    File,
}

impl CellRole {
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

/// One Morphir block of a section: its `yaml morphir:<role>` metadata fence and the source fence
/// after it. A golden block with `expected_file` has no source fence, and its source is empty.
#[derive(Debug)]
pub(super) struct Cell {
    /// The block's `id`, unique in its section.
    pub(super) id: String,
    /// What the block is, from its metadata fence marker.
    pub(super) role: CellRole,
    /// The metadata fence's fields without `id`. A command, assertion or golden block also has
    /// `kind` (`command`, `assertion` or `golden`), and a file block also has `language`, the
    /// source fence's language.
    pub(super) metadata: Map<String, Value>,
    /// The source fence's text, exactly as written.
    pub(super) source: String,
    /// The metadata fence's 1-based line in the source `scenarios.md` file, so that a reader can
    /// point a failure at the block and not at the section heading.
    pub(super) line: usize,
}

/// One `##` section of a `scenarios.md` file: its resolved id, its heading title and line, the
/// scenario metadata `model::parse` reads, and its Morphir blocks in source order.
#[derive(Debug)]
pub(super) struct ParsedSection {
    /// The section's id: explicit (`{#id}`) or derived from its title.
    pub(super) id: String,
    /// The section heading's text.
    pub(super) title: String,
    /// The section heading's 1-based line in the source `scenarios.md` file.
    pub(super) line: usize,
    /// The scenario metadata: the frontmatter's fields, with the heading's text as the `title`.
    pub(super) metadata: Map<String, Value>,
    /// The section's Morphir blocks, in source order.
    pub(super) cells: Vec<Cell>,
}

impl ParsedSection {
    /// The block whose id is `id`, if the section has one.
    pub(super) fn cell(&self, id: &str) -> Option<&Cell> {
        self.cells.iter().find(|cell| cell.id == id)
    }
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

fn items(text: &str) -> Vec<Item> {
    let mut items = Vec::new();
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
                    Tag::CodeBlock(CodeBlockKind::Fenced(info)) => items.push(Item::Fence {
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
                    items.push(Item::Scenario { title, id, start });
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
    items
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

fn cell(
    role: CellRole,
    mut metadata: Map<String, Value>,
    info: &str,
    source: &str,
    line: usize,
) -> Result<Cell> {
    let id = metadata.remove("id").context("Morphir block needs an id")?;
    let id = id
        .as_str()
        .context("Morphir block id must be a string")?
        .to_owned();
    let language = info
        .split_whitespace()
        .next()
        .context("Morphir source fence needs a source language")?;
    ensure!(
        !metadata.contains_key("kind"),
        "block kind comes from the metadata fence marker"
    );
    match role {
        CellRole::File => {
            ensure!(
                !metadata.contains_key("language"),
                "file language comes from the source fence"
            );
            metadata.insert("language".into(), json!(language));
        }
        CellRole::Golden => {
            metadata.insert("kind".into(), json!("golden"));
        }
        CellRole::Command | CellRole::Assertion => {
            let kind = if role == CellRole::Command {
                "command"
            } else {
                ensure!(language == "rego", "assertion source language must be rego");
                "assertion"
            };
            metadata.insert("kind".into(), json!(kind));
        }
    }
    Ok(Cell {
        id,
        role,
        metadata,
        source: source.to_owned(),
        line,
    })
}

/// The metadata of a `morphir:file` block: its portable workspace path, and the language of its
/// source fence.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileMetadata {
    path: String,
    language: String,
}

/// Checks the blocks of one section together: every id is well formed and unique, every file
/// block has valid metadata, and the file paths form one portable workspace.
fn check_cells(cells: &[Cell]) -> Result<()> {
    let mut ids = HashSet::new();
    let mut files = Vec::new();
    for cell in cells {
        let id = &cell.id;
        ensure!(
            !id.is_empty()
                && id.len() <= 64
                && id
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c)),
            "invalid Morphir block id {id:?}"
        );
        ensure!(ids.insert(id.as_str()), "duplicate Morphir block id {id:?}");
        if cell.role == CellRole::File {
            let file: FileMetadata =
                serde_json::from_value(Value::Object(cell.metadata.clone()))
                    .with_context(|| format!("block {id}: invalid workspace file metadata"))?;
            ensure!(
                !file.language.trim().is_empty(),
                "block {id}: file language is empty"
            );
            files.push(file.path);
        }
    }
    super::workspace::validate_workspace_paths(files.iter().map(String::as_str), std::iter::empty())
}

/// Parses a `scenarios.md` file into its frontmatter metadata and its `##` sections. This is the
/// single Markdown pass: [`super::reader::read_scenarios_md`] builds on it, so the file is never
/// parsed twice.
pub(super) fn parse_sections(text: &str) -> Result<ParsedDocument> {
    let (frontmatter_metadata, defaults, body) = frontmatter(text)?;
    let body_offset = text.len() - body.len();
    let prefix_lines = text[..body_offset].bytes().filter(|c| *c == b'\n').count();
    let mut sections: Vec<ParsedSection> = Vec::new();
    let mut ids = HashSet::new();
    let mut pending = None;
    for item in items(body) {
        match item {
            Item::Scenario { title, id, start } => {
                ensure!(
                    pending.is_none(),
                    "metadata needs a source fence before the next scenario heading"
                );
                ensure!(!title.trim().is_empty(), "scenario heading needs a title");
                let id = section_id(&title, id)?;
                ensure!(ids.insert(id.clone()), "duplicate scenario id {id:?}");
                let line = prefix_lines + body[..start].bytes().filter(|c| *c == b'\n').count() + 1;
                let mut metadata = defaults.clone();
                metadata.insert("title".into(), json!(title));
                sections.push(ParsedSection {
                    id,
                    title,
                    line,
                    metadata,
                    cells: Vec::new(),
                });
            }
            Item::Fence {
                info,
                range,
                top_level,
            } => {
                let line = body[..range.start].bytes().filter(|c| *c == b'\n').count() + 1;
                let absolute_line = prefix_lines + line;
                let role = CellRole::from_info(&info)
                    .with_context(|| format!("Markdown body line {line}"))?;
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
                    let Some(section) = sections.last_mut() else {
                        bail!("Morphir block needs a preceding level-two scenario heading");
                    };
                    ensure!(
                        pending.is_none(),
                        "metadata needs a source fence before another metadata fence"
                    );
                    let metadata =
                        yaml(source).with_context(|| format!("Markdown body line {line}"))?;
                    if role == CellRole::Golden && metadata.contains_key("expected_file") {
                        // A disk expectation has no inline source fence.
                        let cell = cell(role, metadata, "text", "", absolute_line)
                            .with_context(|| format!("Markdown body line {line}"))?;
                        section.cells.push(cell);
                    } else {
                        pending = Some((role, metadata, absolute_line));
                    }
                } else if let Some((role, metadata, metadata_line)) = pending.take() {
                    let cell = cell(role, metadata, &info, source, metadata_line)
                        .with_context(|| format!("Markdown body line {line}"))?;
                    sections
                        .last_mut()
                        .expect("a pending block has a section")
                        .cells
                        .push(cell);
                }
            }
        }
    }
    ensure!(pending.is_none(), "metadata needs a following source fence");
    ensure!(
        !sections.is_empty(),
        "Markdown document needs at least one level-two scenario heading"
    );
    for section in &sections {
        check_cells(&section.cells).with_context(|| format!("Markdown scenario {}", section.id))?;
    }
    Ok(ParsedDocument {
        metadata: frontmatter_metadata,
        sections,
    })
}
