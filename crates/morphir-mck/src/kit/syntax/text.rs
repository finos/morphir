//! Text rules the kit grammar inherited from its first driver, which was
//! written in TypeScript. Whitespace and ordering follow ECMAScript so the
//! same kit parses to the same cases and hashes to the same digest.

use std::cmp::Ordering;

/// ECMAScript `WhiteSpace` and `LineTerminator`, the set `\s` and `trim()` use.
/// It differs from `char::is_whitespace` on U+0085 (not included) and U+FEFF
/// (included).
pub fn is_js_whitespace(c: char) -> bool {
    matches!(
        c,
        '\u{0009}'..='\u{000D}'
            | '\u{0020}'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200A}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
            | '\u{FEFF}'
    )
}

/// ECMAScript `LineTerminator`: the characters `.` does not match.
pub fn is_js_line_terminator(c: char) -> bool {
    matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')
}

pub fn js_trim(text: &str) -> &str {
    text.trim_matches(is_js_whitespace)
}

pub fn js_trim_start(text: &str) -> &str {
    text.trim_start_matches(is_js_whitespace)
}

pub fn is_js_blank(text: &str) -> bool {
    text.chars().all(is_js_whitespace)
}

/// `text.trim().split(/\s+/)` without the empty tokens.
pub fn js_tokens(text: &str) -> impl Iterator<Item = &str> {
    text.split(is_js_whitespace).filter(|t| !t.is_empty())
}

/// `source.split(/\r?\n/)`, dropping the final empty element a trailing
/// newline produces so line numbers match an editor's.
pub fn split_lines(source: &str) -> Vec<&str> {
    let mut lines: Vec<&str> = source.split('\n').collect();
    // Only a `\r` that precedes a `\n` belongs to the separator.
    let terminated = lines.len() - 1;
    for line in &mut lines[..terminated] {
        *line = line.strip_suffix('\r').unwrap_or(line);
    }
    if lines.last() == Some(&"") {
        lines.pop();
    }
    lines
}

/// The match of `(.+?)` followed by a tail that `accepts` must take to the
/// end of the text: the shortest non-empty prefix free of line terminators
/// whose remainder the tail accepts.
pub fn lazy_prefix<'a, T>(
    text: &'a str,
    mut accepts: impl FnMut(&'a str) -> Option<T>,
) -> Option<(&'a str, T)> {
    let mut boundaries = text
        .char_indices()
        .map(|(i, _)| i)
        .skip(1)
        .chain([text.len()]);
    let mut chars = text.chars();
    loop {
        let end = boundaries.next()?;
        if is_js_line_terminator(chars.next()?) {
            return None;
        }
        if let Some(tail) = accepts(&text[end..]) {
            return Some((&text[..end], tail));
        }
    }
}

/// Default ECMAScript string order: by UTF-16 code unit. It disagrees with
/// `str` ordering for characters above U+FFFF, which sort as surrogates.
pub fn utf16_cmp(a: &str, b: &str) -> Ordering {
    a.encode_utf16().cmp(b.encode_utf16())
}

/// `Number.parseInt(text, 10)`: optional whitespace, an optional sign and the
/// longest run of decimal digits. `None` is `NaN`.
pub fn js_parse_int(text: &str) -> Option<i64> {
    let text = js_trim_start(text);
    let (negative, digits) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.strip_prefix('+').unwrap_or(text)),
    };
    let end = digits
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(digits.len());
    let magnitude: i64 = digits[..end].parse().ok()?;
    Some(if negative { -magnitude } else { magnitude })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whitespace_follows_ecmascript_not_unicode_white_space() {
        assert!(is_js_whitespace('\u{FEFF}'));
        assert!(!is_js_whitespace('\u{0085}'));
        assert!(is_js_whitespace('\u{00A0}'));
        assert_eq!(js_trim("\u{FEFF} a b \t"), "a b");
    }

    #[test]
    fn lines_split_on_lf_and_crlf_and_drop_the_trailing_empty_line() {
        assert_eq!(split_lines("a\r\nb\n"), vec!["a", "b"]);
        assert_eq!(split_lines("a\n\n"), vec!["a", ""]);
        assert_eq!(split_lines(""), Vec::<&str>::new());
        assert_eq!(split_lines("a\rb"), vec!["a\rb"]);
        assert_eq!(split_lines("a\r"), vec!["a\r"]);
    }

    #[test]
    fn lazy_prefix_takes_the_shortest_prefix_the_tail_accepts() {
        let blank = |rest: &str| is_js_blank(rest).then_some(());
        assert_eq!(lazy_prefix("title  ", blank).map(|m| m.0), Some("title"));
        assert_eq!(lazy_prefix("  ", blank).map(|m| m.0), Some(" "));
        assert_eq!(lazy_prefix("", blank).map(|m| m.0), None);
        assert_eq!(lazy_prefix("a\rb", blank).map(|m| m.0), None);
    }

    #[test]
    fn utf16_order_puts_astral_characters_before_high_bmp_characters() {
        assert_eq!(utf16_cmp("\u{1F600}", "\u{FF5E}"), Ordering::Less);
        assert_eq!("\u{1F600}".cmp("\u{FF5E}"), Ordering::Greater);
        assert_eq!(utf16_cmp("B", "a"), Ordering::Less);
    }

    #[test]
    fn parse_int_reads_a_leading_integer() {
        assert_eq!(js_parse_int("4"), Some(4));
        assert_eq!(js_parse_int(" +4x"), Some(4));
        assert_eq!(js_parse_int("-3"), Some(-3));
        assert_eq!(js_parse_int("x4"), None);
        assert_eq!(js_parse_int(""), None);
    }
}
