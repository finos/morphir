//! The Markdown kit and its `.feature` twin hold the same cases.
//!
//! For each of the kit's 8 Markdown case files, the test parses the Markdown,
//! converts the cases to `.feature` text, reads that text through
//! `morphir-gherkin`, and lowers the document back to kit cases. Every case
//! must come back equal on its id, title, node, version, status, compare and
//! prose, and every fence equal on its info and body, in order. The lowering
//! must report no errors, and the kit must hold 131 cases. The feature's
//! description must be the Markdown file's introduction, and the fence map must
//! hold every fence once, under the line of the step that gives it.

use std::path::{Path, PathBuf};

use morphir_mck::kit::KitCase;
use morphir_mck::kit::gherkin::convert::{convert, feature_description, feature_title};
use morphir_mck::kit::gherkin::lower::lower;
use morphir_mck::kit::syntax::case::parse_kit_file;

const FILES: [&str; 8] = [
    "definitions",
    "distributions",
    "document-tree",
    "names",
    "patterns-and-literals",
    "types",
    "values",
    "versions",
];

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The first field on which `lowered` differs from `markdown`, if any.
fn first_difference(markdown: &KitCase, lowered: &KitCase) -> Option<String> {
    let case_fields = [
        ("id", markdown.id != lowered.id),
        ("title", markdown.title != lowered.title),
        ("node", markdown.node != lowered.node),
        ("version", markdown.version != lowered.version),
        ("status", markdown.status != lowered.status),
        ("compare", markdown.compare != lowered.compare),
        ("prose", markdown.prose != lowered.prose),
        ("fence count", markdown.fences.len() != lowered.fences.len()),
    ];
    if let Some((field, _)) = case_fields.iter().find(|(_, differs)| *differs) {
        return Some(format!(
            "{field}: markdown {:?}, lowered {:?}",
            field_value(markdown, field),
            field_value(lowered, field)
        ));
    }
    for (index, (want, got)) in markdown.fences.iter().zip(&lowered.fences).enumerate() {
        if want.info != got.info {
            return Some(format!(
                "fence {index} info: markdown {:?}, lowered {:?}",
                want.info, got.info
            ));
        }
        if want.body != got.body {
            return Some(format!(
                "fence {index} body: markdown {:?}, lowered {:?}",
                want.body, got.body
            ));
        }
        if got.index != index {
            return Some(format!("fence {index} index: lowered {}", got.index));
        }
    }
    None
}

fn field_value(case: &KitCase, field: &str) -> String {
    match field {
        "id" => case.id.to_string(),
        "title" => case.title.clone(),
        "node" => format!("{:?}", case.node),
        "version" => format!("{:?}", case.version),
        "status" => format!("{:?}", case.status),
        "compare" => format!("{:?}", case.compare),
        "prose" => format!("{:?}", case.prose),
        _ => case.fences.len().to_string(),
    }
}

#[test]
fn every_markdown_case_survives_the_trip_through_a_feature_file() {
    let mut total = 0;
    let mut mismatches = Vec::new();
    for topic in FILES {
        let markdown_path = format!("spec/ir/mck/{topic}.md");
        let source = std::fs::read_to_string(repo().join(&markdown_path))
            .unwrap_or_else(|e| panic!("cannot read {markdown_path}: {e}"));
        let parsed = parse_kit_file(&markdown_path, &source);
        assert_eq!(parsed.errors, vec![], "{markdown_path} parses cleanly");

        let feature_path = format!("spec/ir/mck/{topic}.feature");
        let introduction = feature_description(&source);
        let text = convert(&feature_title(topic, &source), &introduction, &parsed.cases);
        let (document, _) = morphir_gherkin::read_str(&feature_path, &text)
            .unwrap_or_else(|e| panic!("{feature_path} does not read: {e}\n{text}"));
        let lowered = lower(&feature_path, &document);
        assert_eq!(
            lowered.parsed.errors,
            vec![],
            "{feature_path} lowers cleanly:\n{text}"
        );
        assert_eq!(
            lowered.parsed.cases.len(),
            parsed.cases.len(),
            "{feature_path} holds every case of {markdown_path}"
        );
        assert_eq!(
            lowered.description, introduction,
            "{feature_path} keeps the file introduction"
        );
        let fence_count: usize = lowered.parsed.cases.iter().map(|c| c.fences.len()).sum();
        assert_eq!(
            lowered.fences.len(),
            fence_count,
            "{feature_path}: one fence map entry per fence"
        );
        for ((path, row, line), fence) in &lowered.fences {
            let target = &lowered.parsed.cases[fence.case].fences[fence.fence];
            assert_eq!(
                target.line, *line,
                "{feature_path}: {path} row {row:?} maps to a fence on its step's line"
            );
        }
        for (markdown, lowered) in parsed.cases.iter().zip(&lowered.parsed.cases) {
            if let Some(difference) = first_difference(markdown, lowered) {
                mismatches.push(format!("{}: {difference}", markdown.id));
            }
        }
        total += lowered.parsed.cases.len();
    }
    assert!(mismatches.is_empty(), "{}", mismatches.join("\n"));
    assert_eq!(total, 131);
}
