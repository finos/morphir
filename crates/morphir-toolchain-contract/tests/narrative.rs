//! Keeps the published toolchain narrative and contract pages honest.
//!
//! Every JSON or TOML example in the narrative must name the fixture it shows
//! in its fence title, match that fixture byte for byte, and read as a valid
//! document. Relative links, anchors and diagrams in the toolchain pages must
//! resolve.

use morphir_toolchain_contract::{read_lock, read_receipt, read_recipe, read_request, read_result};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

const NARRATIVE: &str = "docs/design/proposals/toolchain-acquisition.md";

/// Pages whose links this test checks: the narrative and the contract pages.
const PAGES: &[&str] = &[
    NARRATIVE,
    "docs/design/proposals/index.md",
    "docs/spec/toolchain/index.md",
    "docs/spec/toolchain/toolset-recipe.md",
    "docs/spec/toolchain/toolchain-request.md",
    "docs/spec/toolchain/toolchain-lock.md",
    "docs/spec/toolchain/installation-receipt.md",
    "docs/spec/toolchain/manager-result.md",
    "docs/spec/tool-release-metadata/index.md",
];

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn read_text(relative: &str) -> String {
    let path = root().join(relative);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
}

struct Fence {
    language: String,
    title: Option<String>,
    body: String,
    line: usize,
}

fn fences(markdown: &str) -> Vec<Fence> {
    let mut fences = Vec::new();
    let mut lines = markdown.lines().enumerate();
    while let Some((number, line)) = lines.next() {
        let Some(info) = line.strip_prefix("```") else {
            continue;
        };
        let language = info
            .split_whitespace()
            .next()
            .unwrap_or_default()
            .to_owned();
        let title = info
            .split_once("title=\"")
            .and_then(|(_, rest)| rest.split_once('"'))
            .map(|(title, _)| title.to_owned());
        let mut body = String::new();
        for (_, line) in lines.by_ref() {
            if line == "```" {
                break;
            }
            body.push_str(line);
            body.push('\n');
        }
        fences.push(Fence {
            language,
            title,
            body,
            line: number + 1,
        });
    }
    fences
}

fn read_as_contract(path: &str, bytes: &[u8]) -> Result<(), String> {
    let contract = path
        .split('/')
        .skip_while(|segment| *segment != "0.1.0-draft.1")
        .nth(1)
        .unwrap_or_default();
    let result = match contract {
        "request" => read_request(bytes).map(drop),
        "lock" => read_lock(bytes).map(drop),
        "recipe" => read_recipe(bytes).map(drop),
        "receipt" => read_receipt(bytes).map(drop),
        "result" => read_result(bytes).map(drop),
        "signed" if path.ends_with(".toml") => read_request(bytes).map(drop),
        "signed" if path.ends_with(".lock.json") => read_lock(bytes).map(drop),
        other => return Err(format!("{path} is not a known contract fixture ({other})")),
    };
    result.map_err(|refusal| format!("{path} is not a valid document: {refusal}"))
}

#[test]
fn every_document_example_is_a_valid_fixture_shown_verbatim() {
    let markdown = read_text(NARRATIVE);
    let mut shown = 0;
    let mut failures = Vec::new();
    for fence in fences(&markdown) {
        if !matches!(fence.language.as_str(), "json" | "toml") {
            continue;
        }
        shown += 1;
        let Some(title) = &fence.title else {
            failures.push(format!(
                "line {}: a {} example must name its fixture in title=\"…\"",
                fence.line, fence.language
            ));
            continue;
        };
        if !title.starts_with("docs/spec/toolchain/fixtures/0.1.0-draft.1/") {
            failures.push(format!(
                "line {}: {title} is not a contract fixture",
                fence.line
            ));
            continue;
        }
        let fixture = read_text(title);
        // A fence always ends its last line; a fixture whose bytes are bound
        // by digest may end without a final newline. That is the only
        // difference allowed.
        let shown_as = if fixture.ends_with('\n') {
            fixture.clone()
        } else {
            format!("{fixture}\n")
        };
        if shown_as != fence.body {
            failures.push(format!(
                "line {}: the example differs from {title}",
                fence.line
            ));
        }
        if let Err(message) = read_as_contract(title, fixture.as_bytes()) {
            failures.push(format!("line {}: {message}", fence.line));
        }
    }
    assert!(shown >= 5, "the narrative shows {shown} document examples");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The heading slugs Docusaurus generates for a Markdown page.
fn anchors(markdown: &str) -> BTreeSet<String> {
    let mut in_fence = false;
    let mut anchors = BTreeSet::new();
    for line in markdown.lines() {
        if line.starts_with("```") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence || !line.starts_with('#') {
            continue;
        }
        let text = line.trim_start_matches('#').trim();
        let slug = text
            .to_lowercase()
            .chars()
            .filter(|character| character.is_alphanumeric() || matches!(character, ' ' | '-' | '_'))
            .collect::<String>()
            .replace(' ', "-");
        anchors.insert(slug);
    }
    anchors
}

fn links(markdown: &str) -> Vec<(bool, String, String)> {
    let mut found = Vec::new();
    let mut in_fence = false;
    for line in markdown.lines() {
        if line.starts_with("```") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence {
            continue;
        }
        let mut rest = line;
        while let Some(start) = rest.find("](") {
            let open = rest[..start].rfind('[').unwrap_or(0);
            let image = open > 0 && rest.as_bytes()[open - 1] == b'!';
            let alt = rest[open + 1..start].to_owned();
            let after = &rest[start + 2..];
            let end = after.find(')').unwrap_or(after.len());
            found.push((image, alt, after[..end].to_owned()));
            rest = &after[end..];
        }
    }
    found
}

fn resolve(page: &Path, target: &str) -> PathBuf {
    if let Some(schema) = target.strip_prefix("/schemas/") {
        return root().join("website/static/schemas").join(schema);
    }
    page.parent().unwrap().join(target)
}

#[test]
fn links_anchors_and_diagrams_in_the_toolchain_pages_resolve() {
    let mut failures = Vec::new();
    let mut diagrams = 0;
    for page in PAGES {
        let markdown = read_text(page);
        let page_path = root().join(page);
        for (image, alt, target) in links(&markdown) {
            if target.starts_with("http://") || target.starts_with("https://") {
                continue;
            }
            let (path, anchor) = target.split_once('#').unwrap_or((&target, ""));
            let file = if path.is_empty() {
                page_path.clone()
            } else {
                resolve(&page_path, path)
            };
            if !file.exists() {
                failures.push(format!("{page}: {target} does not exist"));
                continue;
            }
            if !anchor.is_empty() {
                let text = std::fs::read_to_string(&file).unwrap();
                if !anchors(&text).contains(anchor) {
                    failures.push(format!("{page}: {target} names a missing heading"));
                }
            }
            if image {
                diagrams += usize::from(*page == NARRATIVE);
                let svg = std::fs::read_to_string(&file).unwrap();
                if alt.trim().is_empty() {
                    failures.push(format!("{page}: {target} has no alternative text"));
                }
                if !svg.contains("role=\"img\"")
                    || !svg.contains("<title")
                    || !svg.contains("<desc")
                {
                    failures.push(format!("{page}: {target} lacks role, title or description"));
                }
            }
        }
    }
    assert_eq!(diagrams, 7, "the narrative carries seven diagrams");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn the_narrative_says_prominently_that_nothing_is_implemented() {
    let markdown = read_text(NARRATIVE);
    let body = markdown.split("---").nth(2).unwrap_or_default();
    let first = body.trim_start();
    assert!(
        first.starts_with("# Toolchain acquisition")
            && body.contains(":::caution Proposed interface, not implemented"),
        "the page opens with the proposal warning"
    );
    for decision in [
        "DEP-1", "UP-1", "UP-2", "FS-1", "LOCK-1", "PATH-1", "QUAL-1",
    ] {
        assert!(markdown.contains(decision), "{decision} is named");
    }
    assert!(
        !markdown.contains("morphir mck"),
        "the narrative names no compatibility runner"
    );
}
