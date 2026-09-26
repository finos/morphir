//! The kit's Gherkin step vocabulary: parsing one step's text, with its
//! optional doc string, into a [`KitStep`], and printing a `KitStep` back as
//! step text. The feature loader and step library share this vocabulary.

use std::sync::LazyLock;

use regex::Regex;

use crate::kit::Language;

/// One kit step, parsed from its text: what fence it stands for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KitStep {
    /// `Given a <Node> whose canonical form is:` with an Ion doc string.
    Reference {
        /// The node the reference denotes.
        node: String,
        /// Its canonical Ion text.
        body: Body,
    },
    /// `Then its canonical <format> spelling is <spelling>` or `…is:` with a doc string.
    Canonical {
        /// The data format the spelling is in.
        format: Format,
        /// The spelling, inline or as a doc string.
        body: Body,
    },
    /// `Then a reader of <format> accepts <input>`, optionally `with warning <code>`.
    Accepted {
        /// The data format the reader reads.
        format: Format,
        /// The accepted input, inline or as a doc string.
        body: Body,
        /// The warning code the reader must report, if any.
        warning: Option<String>,
    },
    /// `Then a reader of <format> rejects <input> with <diagnostic>`.
    Rejected {
        /// The data format the reader reads.
        format: Format,
        /// The rejected input, inline or as a doc string.
        body: Body,
        /// The diagnostic the reader must report.
        diagnostic: String,
    },
    /// `Then a reader of <format> reads <input> as a <Node>`.
    ReadsAs {
        /// The data format the reader reads.
        format: Format,
        /// The input, inline or as a doc string.
        body: Body,
        /// The node kind the reader must produce.
        node: String,
    },
    /// `Given the tree file "<path>" in set "<set>":`, `Given the tree file "<path>":`, and the
    /// read-only forms `Given the read-only tree file "<path>" in set "<set>":` and
    /// `Given the read-only tree file "<path>":`. All take a doc string.
    TreeFile {
        /// The file's repository-relative path.
        path: String,
        /// The set the file belongs to; `None` is the anonymous set.
        set: Option<String>,
        /// Whether the file is read-only: excluded from the canonical write-back check.
        read_only: bool,
        /// The file's content, as a doc string.
        body: Body,
    },
    /// `Then the "<set>" tree reads back as the canonical form`, or `Then the tree reads back as
    /// the canonical form` for the unnamed set. It carries no fence.
    TreeCheck {
        /// The set to check; `None` is the anonymous set.
        set: Option<String>,
    },
}

/// The format word in a step: `YAML`, `JSON` or `text`. The info-string language is its lowercase.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    /// `YAML`, info-string language `yaml`.
    Yaml,
    /// `JSON`, info-string language `json`.
    Json,
    /// `Ion`, info-string language `ion`.
    Ion,
    /// `text`, info-string language `text`.
    Text,
}

impl Format {
    /// The fence info-string language this format's steps carry.
    pub fn language(self) -> Language {
        match self {
            Self::Yaml => Language::Yaml,
            Self::Json => Language::Json,
            Self::Ion => Language::Ion,
            Self::Text => Language::Text,
        }
    }

    /// The word this format prints as, in step text: `YAML`, `JSON` or `text`.
    pub fn word(self) -> &'static str {
        match self {
            Self::Yaml => "YAML",
            Self::Json => "JSON",
            Self::Ion => "Ion",
            Self::Text => "text",
        }
    }

    /// Parses a matcher's captured format word. The matchers only ever capture
    /// `YAML`, `JSON` or `text`, so any other word is a bug in a matcher.
    fn parse(word: &str) -> Self {
        match word {
            "YAML" => Self::Yaml,
            "JSON" => Self::Json,
            "Ion" => Self::Ion,
            "text" => Self::Text,
            other => unreachable!("matcher captured an unknown format word \"{other}\""),
        }
    }
}

/// Where a step's document is: inline (a table cell or quoted text, which has no newline) or a
/// doc string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Body {
    /// The document inline in the step text, kept exactly as captured.
    Inline(String),
    /// The document as the step's doc string.
    DocString {
        /// The doc string's content type tag, if any (for example `yaml`).
        content_type: Option<String>,
        /// The doc string's text.
        text: String,
    },
}

macro_rules! step_regex {
    ($name:ident, $pattern:expr) => {
        static $name: LazyLock<Regex> =
            LazyLock::new(|| Regex::new($pattern).expect("valid regex"));
    };
}

step_regex!(
    CANONICAL_DOC,
    r"^its canonical (YAML|JSON|Ion|text) spelling is:$"
);
step_regex!(REFERENCE_DOC, r"^an? (\S+) whose canonical form is:$");
step_regex!(
    CANONICAL_INLINE,
    r"^its canonical (YAML|JSON|Ion|text) spelling is (.+)$"
);
step_regex!(
    ACCEPTED_WARNING_DOC,
    r"^a reader of (YAML|JSON|Ion|text) accepts with warning (\S+):$"
);
step_regex!(
    ACCEPTED_WARNING_INLINE,
    r"^a reader of (YAML|JSON|Ion|text) accepts (.+) with warning (\S+)$"
);
step_regex!(ACCEPTED_DOC, r"^a reader of (YAML|JSON|Ion|text) accepts:$");
step_regex!(
    ACCEPTED_INLINE,
    r"^a reader of (YAML|JSON|Ion|text) accepts (.+)$"
);
step_regex!(
    REJECTED_DOC,
    r"^a reader of (YAML|JSON|Ion|text) rejects with (\S+):$"
);
step_regex!(
    REJECTED_INLINE,
    r"^a reader of (YAML|JSON|Ion|text) rejects (.+) with (\S+)$"
);
step_regex!(
    READS_AS_DOC,
    r"^a reader of (YAML|JSON|Ion|text) reads as an? (\S+):$"
);
step_regex!(
    READS_AS_INLINE,
    r"^a reader of (YAML|JSON|Ion|text) reads (.+) as an? (\S+)$"
);
step_regex!(
    TREE_FILE,
    r#"^the (read-only )?tree file "([^"]+)"(?: in set "([^"]+)")?:$"#
);
step_regex!(
    TREE_CHECK_SET,
    r#"^the "([^"]+)" tree reads back as the canonical form$"#
);
step_regex!(TREE_CHECK, r"^the tree reads back as the canonical form$");

/// Requires a doc string, and checks its content type against `format`'s language.
fn doc_string_body(
    doc_string: Option<(&Option<String>, &str)>,
    format: Format,
) -> Result<Body, String> {
    let Some((content_type, text)) = doc_string else {
        return Err("this step needs a doc string".to_owned());
    };
    if let Some(content_type) = content_type
        && content_type != format.language().as_str()
    {
        return Err(format!(
            "doc string content type \"{content_type}\" does not match format {}",
            format.word()
        ));
    }
    Ok(Body::DocString {
        content_type: content_type.clone(),
        text: text.to_owned(),
    })
}

/// Requires a doc string, with no content type to check against (a tree file
/// carries no format).
fn tree_file_body(doc_string: Option<(&Option<String>, &str)>) -> Result<Body, String> {
    let Some((content_type, text)) = doc_string else {
        return Err("this step needs a doc string".to_owned());
    };
    Ok(Body::DocString {
        content_type: content_type.clone(),
        text: text.to_owned(),
    })
}

/// Requires no doc string: this step's document, if any, is inline.
fn no_doc_string(doc_string: Option<(&Option<String>, &str)>) -> Result<(), String> {
    if doc_string.is_some() {
        return Err("this step has a doc string it should not have".to_owned());
    }
    Ok(())
}

/// Parses one step's text, with its doc string if any. `None` means the text is not a kit step.
pub fn parse_step(
    text: &str,
    doc_string: Option<(&Option<String>, &str)>,
) -> Option<Result<KitStep, String>> {
    if let Some(caps) = REFERENCE_DOC.captures(text) {
        return Some(
            doc_string_body(doc_string, Format::Ion).map(|body| KitStep::Reference {
                node: caps[1].to_owned(),
                body,
            }),
        );
    }
    if let Some(caps) = CANONICAL_DOC.captures(text) {
        let format = Format::parse(&caps[1]);
        return Some(
            doc_string_body(doc_string, format).map(|body| KitStep::Canonical { format, body }),
        );
    }
    if let Some(caps) = CANONICAL_INLINE.captures(text) {
        let format = Format::parse(&caps[1]);
        let inline = caps[2].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::Canonical {
            format,
            body: Body::Inline(inline),
        }));
    }
    if let Some(caps) = ACCEPTED_WARNING_DOC.captures(text) {
        let format = Format::parse(&caps[1]);
        let warning = caps[2].to_owned();
        return Some(
            doc_string_body(doc_string, format).map(|body| KitStep::Accepted {
                format,
                body,
                warning: Some(warning),
            }),
        );
    }
    if let Some(caps) = ACCEPTED_WARNING_INLINE.captures(text) {
        let format = Format::parse(&caps[1]);
        let inline = caps[2].to_owned();
        let warning = caps[3].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::Accepted {
            format,
            body: Body::Inline(inline),
            warning: Some(warning),
        }));
    }
    if let Some(caps) = ACCEPTED_DOC.captures(text) {
        let format = Format::parse(&caps[1]);
        return Some(
            doc_string_body(doc_string, format).map(|body| KitStep::Accepted {
                format,
                body,
                warning: None,
            }),
        );
    }
    if let Some(caps) = ACCEPTED_INLINE.captures(text) {
        let format = Format::parse(&caps[1]);
        let inline = caps[2].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::Accepted {
            format,
            body: Body::Inline(inline),
            warning: None,
        }));
    }
    if let Some(caps) = REJECTED_DOC.captures(text) {
        let format = Format::parse(&caps[1]);
        let diagnostic = caps[2].to_owned();
        return Some(
            doc_string_body(doc_string, format).map(|body| KitStep::Rejected {
                format,
                body,
                diagnostic,
            }),
        );
    }
    if let Some(caps) = REJECTED_INLINE.captures(text) {
        let format = Format::parse(&caps[1]);
        let inline = caps[2].to_owned();
        let diagnostic = caps[3].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::Rejected {
            format,
            body: Body::Inline(inline),
            diagnostic,
        }));
    }
    if let Some(caps) = READS_AS_DOC.captures(text) {
        let format = Format::parse(&caps[1]);
        let node = caps[2].to_owned();
        return Some(
            doc_string_body(doc_string, format).map(|body| KitStep::ReadsAs { format, body, node }),
        );
    }
    if let Some(caps) = READS_AS_INLINE.captures(text) {
        let format = Format::parse(&caps[1]);
        let inline = caps[2].to_owned();
        let node = caps[3].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::ReadsAs {
            format,
            body: Body::Inline(inline),
            node,
        }));
    }
    if let Some(caps) = TREE_FILE.captures(text) {
        let read_only = caps.get(1).is_some();
        let path = caps[2].to_owned();
        let set = caps.get(3).map(|m| m.as_str().to_owned());
        return Some(tree_file_body(doc_string).map(|body| KitStep::TreeFile {
            path,
            set,
            read_only,
            body,
        }));
    }
    if let Some(caps) = TREE_CHECK_SET.captures(text) {
        let set = caps[1].to_owned();
        return Some(no_doc_string(doc_string).map(|()| KitStep::TreeCheck { set: Some(set) }));
    }
    if TREE_CHECK.is_match(text) {
        return Some(no_doc_string(doc_string).map(|()| KitStep::TreeCheck { set: None }));
    }
    None
}

/// The indefinite article `step_text` prints before a node kind: `an` before a
/// vowel, `a` otherwise.
fn indefinite_article(word: &str) -> &'static str {
    match word.chars().next() {
        Some(letter) if "AEIOUaeiou".contains(letter) => "an",
        _ => "a",
    }
}

/// The step text the converter writes for `step`, without a doc string.
pub fn step_text(step: &KitStep) -> String {
    match step {
        KitStep::Reference { node, .. } => {
            format!(
                "{} {node} whose canonical form is:",
                indefinite_article(node)
            )
        }
        KitStep::Canonical { format, body } => match body {
            Body::Inline(inline) => format!("its canonical {} spelling is {inline}", format.word()),
            Body::DocString { .. } => format!("its canonical {} spelling is:", format.word()),
        },
        KitStep::Accepted {
            format,
            body,
            warning,
        } => match (body, warning) {
            (Body::Inline(inline), Some(warning)) => {
                format!(
                    "a reader of {} accepts {inline} with warning {warning}",
                    format.word()
                )
            }
            (Body::Inline(inline), None) => {
                format!("a reader of {} accepts {inline}", format.word())
            }
            (Body::DocString { .. }, Some(warning)) => {
                format!(
                    "a reader of {} accepts with warning {warning}:",
                    format.word()
                )
            }
            (Body::DocString { .. }, None) => format!("a reader of {} accepts:", format.word()),
        },
        KitStep::Rejected {
            format,
            body,
            diagnostic,
        } => match body {
            Body::Inline(inline) => {
                format!(
                    "a reader of {} rejects {inline} with {diagnostic}",
                    format.word()
                )
            }
            Body::DocString { .. } => {
                format!("a reader of {} rejects with {diagnostic}:", format.word())
            }
        },
        KitStep::ReadsAs { format, body, node } => {
            let article = indefinite_article(node);
            match body {
                Body::Inline(inline) => {
                    format!(
                        "a reader of {} reads {inline} as {article} {node}",
                        format.word()
                    )
                }
                Body::DocString { .. } => {
                    format!("a reader of {} reads as {article} {node}:", format.word())
                }
            }
        }
        KitStep::TreeFile {
            path,
            set,
            read_only,
            ..
        } => {
            let mut text = String::from("the ");
            if *read_only {
                text.push_str("read-only ");
            }
            text.push_str(&format!("tree file \"{path}\""));
            if let Some(set) = set {
                text.push_str(&format!(" in set \"{set}\""));
            }
            text.push(':');
            text
        }
        KitStep::TreeCheck { set: Some(set) } => {
            format!("the \"{set}\" tree reads back as the canonical form")
        }
        KitStep::TreeCheck { set: None } => "the tree reads back as the canonical form".to_owned(),
    }
}

/// Whether `body` can be written inline, in step text or a table cell, and
/// still parse back to itself unchanged. `step_text` does not call this; the
/// converter calls it to choose between an inline body and a doc string.
///
/// `body` is unsafe to inline when it is empty; contains `\n`, `\r` or `|`;
/// contains one of the separators an inline matcher looks for (` with
/// warning `, ` with `, ` as a ` or ` as an `); or starts or ends with
/// whitespace.
pub fn inline_safe(body: &str) -> bool {
    if body.is_empty() {
        return false;
    }
    if body.contains(['\n', '\r', '|']) {
        return false;
    }
    if body.contains(" with warning ")
        || body.contains(" with ")
        || body.contains(" as a ")
        || body.contains(" as an ")
    {
        return false;
    }
    if body.trim() != body {
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_step_form_parses_and_prints_back() {
        let cases = [
            (
                "its canonical YAML spelling is Reference: morphir/SDK:basics#add",
                None,
            ),
            (
                "a reader of JSON accepts \"morphir/SDK:basics#add\" with warning legacy_spelling",
                None,
            ),
            (
                "a reader of JSON rejects { \"x\": 1 } with unknown_member",
                None,
            ),
            ("a reader of YAML reads [ a ] as a Tuple", None),
            (
                "the \"v3-meta\" tree reads back as the canonical form",
                None,
            ),
        ];
        for (text, doc) in cases {
            let step = parse_step(text, doc).expect("a kit step").expect("valid");
            assert_eq!(step_text(&step), text);
        }
    }

    #[test]
    fn a_doc_string_step_keeps_its_body_and_checks_its_content_type() {
        let yaml = Some("yaml".to_owned());
        let s = parse_step("its canonical YAML spelling is:", Some((&yaml, "a: 1\n")))
            .unwrap()
            .unwrap();
        assert_eq!(
            s,
            KitStep::Canonical {
                format: Format::Yaml,
                body: Body::DocString {
                    content_type: yaml.clone(),
                    text: "a: 1\n".into()
                }
            }
        );
        let json = Some("json".to_owned());
        assert!(
            parse_step("its canonical YAML spelling is:", Some((&json, "{}")))
                .unwrap()
                .is_err()
        );
    }

    #[test]
    fn text_that_is_not_a_kit_step_is_none() {
        assert!(parse_step("I run \"morphir x\"", None).is_none());
    }

    #[test]
    fn reads_as_an_int_round_trips() {
        let text = "a reader of JSON reads 42 as an Int";
        let step = parse_step(text, None).expect("a kit step").expect("valid");
        assert_eq!(
            step,
            KitStep::ReadsAs {
                format: Format::Json,
                body: Body::Inline("42".to_owned()),
                node: "Int".to_owned(),
            }
        );
        assert_eq!(step_text(&step), text);
    }

    #[test]
    fn inline_safe_refuses_each_forbidden_case() {
        assert!(!inline_safe(""));
        assert!(!inline_safe("line one\nline two"));
        assert!(!inline_safe("carriage\rreturn"));
        assert!(!inline_safe("a | b"));
        assert!(!inline_safe("accepts x with warning legacy_spelling"));
        assert!(!inline_safe("rejects x with unknown_member"));
        assert!(!inline_safe("reads x as a Tuple"));
        assert!(!inline_safe("reads x as an Int"));
        assert!(!inline_safe(" leading space"));
        assert!(!inline_safe("trailing space "));
    }

    #[test]
    fn inline_safe_bodies_round_trip_through_every_inline_step_form() {
        let bodies = [
            "{ \"Reference\": \"morphir/SDK:basics#add\" }",
            "Reference: morphir/SDK:basics#add",
            "\"morphir/SDK:basics#add\"",
        ];
        for body in bodies {
            assert!(inline_safe(body), "expected {body:?} to be inline-safe");

            let steps = [
                KitStep::Canonical {
                    format: Format::Yaml,
                    body: Body::Inline(body.to_owned()),
                },
                KitStep::Accepted {
                    format: Format::Json,
                    body: Body::Inline(body.to_owned()),
                    warning: None,
                },
                KitStep::Accepted {
                    format: Format::Json,
                    body: Body::Inline(body.to_owned()),
                    warning: Some("legacy_spelling".to_owned()),
                },
                KitStep::Rejected {
                    format: Format::Json,
                    body: Body::Inline(body.to_owned()),
                    diagnostic: "unknown_member".to_owned(),
                },
                KitStep::ReadsAs {
                    format: Format::Yaml,
                    body: Body::Inline(body.to_owned()),
                    node: "Tuple".to_owned(),
                },
            ];
            for step in steps {
                let text = step_text(&step);
                let parsed = parse_step(&text, None).expect("a kit step").expect("valid");
                assert_eq!(parsed, step, "round trip through {text:?}");
            }
        }
    }
}
