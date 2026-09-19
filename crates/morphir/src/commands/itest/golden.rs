use anyhow::{Result, bail, ensure};
use serde::Deserialize;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub enum Selection {
    #[default]
    All,
    Lines {
        start: usize,
        end: usize,
    },
    Between {
        start: String,
        end: String,
    },
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum SelectionRepr {
    All {},
    Lines { start: usize, end: usize },
    Between { start: String, end: String },
}

impl<'de> Deserialize<'de> for Selection {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        Ok(match SelectionRepr::deserialize(deserializer)? {
            SelectionRepr::All {} => Self::All,
            SelectionRepr::Lines { start, end } => Self::Lines { start, end },
            SelectionRepr::Between { start, end } => Self::Between { start, end },
        })
    }
}

impl Selection {
    pub fn validate(&self) -> Result<()> {
        match self {
            Self::All => Ok(()),
            Self::Lines { start, end } => {
                ensure!(*start > 0, "line selection start must be at least 1");
                ensure!(*end >= *start, "line selection end must be at least start");
                Ok(())
            }
            Self::Between { start, end } => {
                ensure!(!start.is_empty(), "start marker must not be empty");
                ensure!(!end.is_empty(), "end marker must not be empty");
                ensure!(start != end, "start and end markers must differ");
                Ok(())
            }
        }
    }

    pub fn select<'a>(&self, text: &'a str) -> Result<&'a str> {
        self.validate()?;
        match self {
            Self::All => Ok(text),
            Self::Lines { start, end } => select_lines(text, *start, *end),
            Self::Between { start, end } => select_between(text, start, end),
        }
    }
}

fn select_lines(text: &str, start: usize, end: usize) -> Result<&str> {
    let lines: Vec<_> = text.split_inclusive('\n').collect();
    ensure!(
        end <= lines.len(),
        "line selection {start}..={end} exceeds {} lines",
        lines.len()
    );
    let start_offset = lines[..start - 1]
        .iter()
        .map(|line| line.len())
        .sum::<usize>();
    let selected_len = lines[start - 1..end]
        .iter()
        .map(|line| line.len())
        .sum::<usize>();
    Ok(&text[start_offset..start_offset + selected_len])
}

fn select_between<'a>(text: &'a str, start: &str, end: &str) -> Result<&'a str> {
    let start_at = unique_occurrence(text, start, "start")?;
    let end_at = unique_occurrence(text, end, "end")?;
    let content_start = start_at + start.len();
    ensure!(
        content_start <= end_at,
        "end marker occurs before or overlaps start marker"
    );
    Ok(&text[content_start..end_at])
}

fn unique_occurrence(text: &str, marker: &str, name: &str) -> Result<usize> {
    let mut matches = Vec::new();
    let mut offset = 0;
    while offset <= text.len() {
        let Some(relative) = text[offset..].find(marker) else {
            break;
        };
        let found = offset + relative;
        matches.push(found);
        if matches.len() > 1 {
            bail!("{name} marker occurs more than once");
        }
        let step = text[found..].chars().next().map_or(1, char::len_utf8);
        offset = found + step;
    }
    matches
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::anyhow!("{name} marker not found"))
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum LineEndings {
    #[default]
    Exact,
    Lf,
}

impl LineEndings {
    pub fn normalize(&self, text: &str) -> String {
        match self {
            Self::Exact => text.to_owned(),
            Self::Lf => text.replace("\r\n", "\n"),
        }
    }
}

/// Renders a bounded diagnostic diff.
///
/// Control characters are escaped for terminal safety, so this output is not
/// intended to be applied as a patch.
pub fn diff(expected: &str, actual: &str) -> String {
    if expected == actual {
        return String::new();
    }

    let expected = lines(expected);
    let actual = lines(actual);
    let prefix = expected
        .iter()
        .zip(&actual)
        .take_while(|(a, b)| a == b)
        .count();
    let suffix = expected[prefix..]
        .iter()
        .rev()
        .zip(actual[prefix..].iter().rev())
        .take_while(|(a, b)| a == b)
        .count();
    let before = prefix.saturating_sub(3);
    let expected_change_end = expected.len() - suffix;
    let actual_change_end = actual.len() - suffix;
    let expected_after = (expected_change_end + 3).min(expected.len());
    let actual_after = (actual_change_end + 3).min(actual.len());

    let mut entries = Vec::new();
    entries.extend(expected[before..prefix].iter().map(|line| (' ', *line)));
    entries.extend(
        expected[prefix..expected_change_end]
            .iter()
            .map(|line| ('-', *line)),
    );
    entries.extend(
        actual[prefix..actual_change_end]
            .iter()
            .map(|line| ('+', *line)),
    );
    entries.extend(
        actual[actual_change_end..actual_after]
            .iter()
            .map(|line| (' ', *line)),
    );

    const LIMIT: usize = 200;
    let truncated = entries.len() > LIMIT;
    if truncated {
        let tail = entries.split_off(entries.len() - (LIMIT / 2 - 1));
        entries.truncate(LIMIT / 2);
        entries.push((
            '!',
            Line {
                text: "... diff truncated ...",
                terminated: true,
            },
        ));
        entries.extend(tail);
    }

    let old_count = expected_after - before;
    let new_count = actual_after - before;
    let mut rendered = format!(
        "--- expected\n+++ actual\n@@ -{},{} +{},{} @@\n",
        before + 1,
        old_count,
        before + 1,
        new_count
    );
    for (prefix, line) in entries {
        rendered.push(prefix);
        push_visible(&mut rendered, line.text);
        rendered.push('\n');
        if !line.terminated {
            rendered.push_str("\\ No newline at end of file\n");
        }
    }
    rendered
}

fn push_visible(output: &mut String, text: &str) {
    const CHARACTER_LIMIT: usize = 1_000;

    let mut characters = text.chars();
    for character in characters.by_ref().take(CHARACTER_LIMIT) {
        if character == '\t' || !character.is_control() {
            output.push(character);
        } else {
            output.extend(character.escape_default());
        }
    }
    if characters.next().is_some() {
        output.push_str("... line truncated ...");
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
struct Line<'a> {
    text: &'a str,
    terminated: bool,
}

fn lines(text: &str) -> Vec<Line<'_>> {
    text.split_inclusive('\n')
        .map(|line| match line.strip_suffix('\n') {
            Some(content) => Line {
                text: content,
                terminated: true,
            },
            None => Line {
                text: line,
                terminated: false,
            },
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_selects_the_whole_input() {
        assert_eq!(
            Selection::All.select("alpha\r\nbeta\n").unwrap(),
            "alpha\r\nbeta\n"
        );
    }

    #[test]
    fn line_selection_is_inclusive_and_keeps_terminators() {
        let selection = Selection::Lines { start: 2, end: 3 };
        assert_eq!(
            selection.select("one\r\ntwo\nthree\rfour").unwrap(),
            "two\nthree\rfour"
        );
    }

    #[test]
    fn line_selection_includes_an_unterminated_last_line() {
        let selection = Selection::Lines { start: 2, end: 2 };
        assert_eq!(selection.select("one\ntwo").unwrap(), "two");
    }

    #[test]
    fn trailing_lf_does_not_add_a_phantom_line() {
        let selection = Selection::Lines { start: 3, end: 3 };
        assert!(selection.select("one\ntwo\n").is_err());
    }

    #[test]
    fn empty_input_has_no_lines() {
        let selection = Selection::Lines { start: 1, end: 1 };
        assert!(selection.select("").is_err());
    }

    #[test]
    fn line_selection_rejects_zero_reversed_and_out_of_range_bounds() {
        for selection in [
            Selection::Lines { start: 0, end: 1 },
            Selection::Lines { start: 2, end: 1 },
            Selection::Lines { start: 1, end: 0 },
        ] {
            assert!(selection.validate().is_err(), "accepted {selection:?}");
        }
        assert!(
            Selection::Lines { start: 1, end: 2 }
                .select("only")
                .is_err()
        );
    }

    #[test]
    fn line_selection_uses_utf8_character_boundaries() {
        let selection = Selection::Lines { start: 2, end: 2 };
        assert_eq!(selection.select("λ\n雪\n").unwrap(), "雪\n");
    }

    #[test]
    fn between_selects_exact_text_excluding_markers() {
        let selection = Selection::Between {
            start: "<start>".into(),
            end: "<end>".into(),
        };
        assert_eq!(
            selection.select("before<start>\r\n雪\n<end>after").unwrap(),
            "\r\n雪\n"
        );
    }

    #[test]
    fn between_rejects_invalid_marker_definitions() {
        for selection in [
            Selection::Between {
                start: "".into(),
                end: "end".into(),
            },
            Selection::Between {
                start: "start".into(),
                end: "".into(),
            },
            Selection::Between {
                start: "same".into(),
                end: "same".into(),
            },
        ] {
            assert!(selection.validate().is_err(), "accepted {selection:?}");
        }
    }

    #[test]
    fn between_requires_each_marker_exactly_once() {
        let selection = Selection::Between {
            start: "aba".into(),
            end: "END".into(),
        };
        assert!(
            selection.select("ababa END").is_err(),
            "overlapping starts must count twice"
        );
        assert!(selection.select("aba END END").is_err());
        assert!(selection.select("aba only").is_err());
        assert!(selection.select("END only").is_err());
    }

    #[test]
    fn between_rejects_reversed_or_overlapping_markers() {
        let reversed = Selection::Between {
            start: "START".into(),
            end: "END".into(),
        };
        assert!(reversed.select("END then START").is_err());

        let overlapping = Selection::Between {
            start: "abc".into(),
            end: "bcd".into(),
        };
        assert!(overlapping.select("abcd").is_err());
    }

    #[test]
    fn line_endings_have_exact_and_crlf_only_modes() {
        let text = "a\r\nb\rc\n雪\r\n";
        assert_eq!(LineEndings::Exact.normalize(text), text);
        assert_eq!(LineEndings::Lf.normalize(text), "a\nb\rc\n雪\n");
    }

    #[test]
    fn serde_defaults_and_rejects_unknown_selection_fields() {
        assert_eq!(Selection::default(), Selection::All);
        assert_eq!(LineEndings::default(), LineEndings::Exact);
        assert_eq!(
            serde_json::from_str::<Selection>(r#"{"kind":"lines","start":2,"end":4}"#).unwrap(),
            Selection::Lines { start: 2, end: 4 }
        );
        assert!(serde_json::from_str::<Selection>(r#"{"kind":"all","extra":true}"#).is_err());
        assert_eq!(
            serde_json::from_str::<LineEndings>(r#""lf""#).unwrap(),
            LineEndings::Lf
        );
    }

    #[test]
    fn diff_is_empty_for_equal_text() {
        assert_eq!(diff("same\n", "same\n"), "");
    }

    #[test]
    fn diff_shows_replacement_context_and_utf8() {
        let rendered = diff("one\n雪\nthree\n", "one\n月\nthree\n");
        assert!(rendered.contains("--- expected\n+++ actual\n"));
        assert!(rendered.contains(" one\n"));
        assert!(rendered.contains("-雪\n"));
        assert!(rendered.contains("+月\n"));
        assert!(rendered.contains(" three\n"));
    }

    #[test]
    fn diff_marks_a_missing_final_newline() {
        let rendered = diff("same", "same\n");
        assert!(rendered.contains("-same\n\\ No newline at end of file\n"));
        assert!(rendered.contains("+same\n"));
    }

    #[test]
    fn diff_makes_carriage_returns_visible() {
        let rendered = diff("a\n", "a\r\n");
        assert!(rendered.contains("-a\n"));
        assert!(rendered.contains("+a\\r\n"));
    }

    #[test]
    fn diff_output_is_bounded() {
        let expected = (0..500).map(|n| format!("old {n}\n")).collect::<String>();
        let actual = (0..500).map(|n| format!("new {n}\n")).collect::<String>();
        let rendered = diff(&expected, &actual);
        assert!(
            rendered.lines().count() <= 210,
            "{} lines",
            rendered.lines().count()
        );
        assert!(rendered.contains("diff truncated"));
    }

    #[test]
    fn diff_truncates_long_lines_on_utf8_boundaries() {
        let expected = format!("{}\n", "雪".repeat(2_000));
        let rendered = diff(&expected, "short\n");
        assert_eq!(rendered.matches('雪').count(), 1_000);
        assert!(rendered.contains("... line truncated ..."));
    }
}
