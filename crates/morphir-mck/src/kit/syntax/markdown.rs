//! Line-oriented tokenizer for MCK case-file markdown. The kit grammar needs
//! only four block kinds (front matter, ATX headings, fenced code, prose), so
//! this is deliberately not a general markdown parser.
//!
//! Rules:
//! - Front matter is a leading `---` line through the next `---` line.
//! - A fence opens with three or more backticks at column 0 and closes with a
//!   line of at least as many backticks and nothing else. Inside a fence every
//!   line is body text, headings included.
//! - A heading is `#` x1..6, a space, and text, outside fences.
//! - Consecutive non-blank lines outside fences form one prose block.

use super::text::{is_js_blank, is_js_line_terminator, js_trim, lazy_prefix, split_lines};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Block {
    FrontMatter {
        text: String,
        line: usize,
    },
    Heading {
        level: usize,
        text: String,
        line: usize,
    },
    Fence {
        info: String,
        body: String,
        line: usize,
        closed: bool,
    },
    Prose {
        text: String,
        line: usize,
    },
}

/// `^(`{3,})(.*)$`: the backtick run and the trimmed info string.
fn fence_open(line: &str) -> Option<(usize, &str)> {
    let ticks = line.chars().take_while(|&c| c == '`').count();
    let rest = &line[ticks..];
    (ticks >= 3 && !rest.contains(is_js_line_terminator)).then(|| (ticks, js_trim(rest)))
}

/// `^`+\s*$` with at least as many backticks as the opening run.
fn fence_close(line: &str, ticks: usize) -> bool {
    let run = line.chars().take_while(|&c| c == '`').count();
    run >= ticks.max(1) && is_js_blank(&line[run..])
}

/// `^(#{1,6}) (.+?)\s*$`
fn heading(line: &str) -> Option<(usize, &str)> {
    let level = line.chars().take_while(|&c| c == '#').count();
    if !(1..=6).contains(&level) {
        return None;
    }
    let text = line[level..].strip_prefix(' ')?;
    let (text, ()) = lazy_prefix(text, |rest| is_js_blank(rest).then_some(()))?;
    Some((level, text))
}

pub fn tokenize(source: &str) -> Vec<Block> {
    let lines = split_lines(source.strip_prefix('\u{FEFF}').unwrap_or(source));
    let mut blocks = Vec::new();
    let mut index = 0;

    if lines.first() == Some(&"---") {
        let stop = lines[1..]
            .iter()
            .position(|&l| l == "---")
            .map_or(lines.len(), |p| p + 1);
        blocks.push(Block::FrontMatter {
            text: lines[1..stop].join("\n"),
            line: 1,
        });
        index = stop + 1;
    }

    let mut prose: Option<(usize, Vec<&str>)> = None;
    let flush = |prose: &mut Option<(usize, Vec<&str>)>, blocks: &mut Vec<Block>| {
        if let Some((line, lines)) = prose.take() {
            blocks.push(Block::Prose {
                text: lines.join("\n"),
                line,
            });
        }
    };

    while index < lines.len() {
        let line = lines[index];
        if let Some((ticks, info)) = fence_open(line) {
            flush(&mut prose, &mut blocks);
            let start = index;
            let mut body = String::new();
            let mut closed = false;
            index += 1;
            while index < lines.len() {
                let candidate = lines[index];
                index += 1;
                if fence_close(candidate, ticks) {
                    closed = true;
                    break;
                }
                body.push_str(candidate);
                body.push('\n');
            }
            blocks.push(Block::Fence {
                info: info.to_owned(),
                body,
                line: start + 1,
                closed,
            });
        } else if let Some((level, text)) = heading(line) {
            flush(&mut prose, &mut blocks);
            blocks.push(Block::Heading {
                level,
                text: text.to_owned(),
                line: index + 1,
            });
            index += 1;
        } else if is_js_blank(line) {
            flush(&mut prose, &mut blocks);
            index += 1;
        } else {
            prose
                .get_or_insert_with(|| (index + 1, Vec::new()))
                .1
                .push(line);
            index += 1;
        }
    }
    flush(&mut prose, &mut blocks);
    blocks
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fence(info: &str, body: &str, line: usize, closed: bool) -> Block {
        Block::Fence {
            info: info.into(),
            body: body.into(),
            line,
            closed,
        }
    }

    #[test]
    fn splits_front_matter_headings_fences_and_prose() {
        let source = [
            "---",
            "kit: ir-v4-encoding",
            "---",
            "# Title",
            "",
            "## types-0001: Something {node=Type}",
            "Some prose.",
            "```yaml canonical",
            "Unit: {}",
            "```",
        ]
        .join("\n");
        assert_eq!(
            tokenize(&source),
            vec![
                Block::FrontMatter {
                    text: "kit: ir-v4-encoding".into(),
                    line: 1
                },
                Block::Heading {
                    level: 1,
                    text: "Title".into(),
                    line: 4
                },
                Block::Heading {
                    level: 2,
                    text: "types-0001: Something {node=Type}".into(),
                    line: 6
                },
                Block::Prose {
                    text: "Some prose.".into(),
                    line: 7
                },
                fence("yaml canonical", "Unit: {}\n", 8, true),
            ]
        );
    }

    #[test]
    fn a_four_backtick_fence_may_contain_three_backtick_fences() {
        let source = ["````markdown", "```yaml canonical", "x: 1", "```", "````"].join("\n");
        assert_eq!(
            tokenize(&source),
            vec![fence("markdown", "```yaml canonical\nx: 1\n```\n", 1, true)]
        );
    }

    #[test]
    fn headings_inside_a_fence_are_body_text() {
        let blocks = tokenize("```text\n## not-a-case-0001: nope\n```");
        assert!(matches!(blocks.as_slice(), [Block::Fence { .. }]));
    }

    #[test]
    fn an_unterminated_fence_runs_to_end_of_file() {
        assert_eq!(
            tokenize("```yaml canonical\na: 1\n"),
            vec![fence("yaml canonical", "a: 1\n", 1, false)]
        );
    }

    #[test]
    fn blank_lines_separate_prose_blocks_and_are_not_emitted() {
        assert_eq!(
            tokenize("one\n\ntwo\n"),
            vec![
                Block::Prose {
                    text: "one".into(),
                    line: 1
                },
                Block::Prose {
                    text: "two".into(),
                    line: 3
                }
            ]
        );
    }

    #[test]
    fn a_leading_bom_is_stripped_before_splitting() {
        assert_eq!(
            tokenize("\u{FEFF}## x"),
            vec![Block::Heading {
                level: 2,
                text: "x".into(),
                line: 1
            }]
        );
    }

    #[test]
    fn seven_hashes_or_a_missing_space_is_prose() {
        assert!(matches!(
            tokenize("####### x").as_slice(),
            [Block::Prose { .. }]
        ));
        assert!(matches!(tokenize("##x").as_slice(), [Block::Prose { .. }]));
    }

    #[test]
    fn an_unclosed_front_matter_swallows_the_file() {
        assert_eq!(
            tokenize("---\na\nb"),
            vec![Block::FrontMatter {
                text: "a\nb".into(),
                line: 1
            }]
        );
    }
}
