//! Custom TOML editor for desktop platform with syntax highlighting.
//! Uses an overlay technique: transparent textarea over highlighted code.

use dioxus::prelude::*;

/// Custom TOML editor for desktop platform.
/// Uses overlay technique for real-time syntax highlighting while typing.
#[component]
pub fn TomlEditor(content: String, on_change: EventHandler<String>) -> Element {
    let mut local_content = use_signal(|| content.clone());

    // Generate highlighted HTML from the current content
    let highlighted_html = use_memo(move || highlight_toml_with_lines(&local_content.read()));

    rsx! {
        div { class: "toml-overlay-editor",
            // Line numbers gutter
            div { class: "toml-line-numbers",
                dangerous_inner_html: "{generate_line_numbers(&local_content.read())}"
            }

            // Editor area with overlay
            div { class: "toml-editor-area",
                // Highlighted code layer (behind)
                pre {
                    class: "toml-highlight-layer",
                    dangerous_inner_html: "{highlighted_html}"
                }

                // Transparent textarea (on top for input)
                textarea {
                    class: "toml-input-layer",
                    value: "{local_content}",
                    spellcheck: false,
                    oninput: move |e| {
                        let new_value = e.value();
                        local_content.set(new_value.clone());
                        on_change.call(new_value);
                    }
                }
            }
        }
    }
}

/// Generates line numbers HTML.
fn generate_line_numbers(code: &str) -> String {
    let line_count = code.lines().count().max(1);
    let mut html = String::new();

    for i in 1..=line_count {
        html.push_str(&format!("<div class=\"line-number\">{}</div>", i));
    }

    // Add extra line if content ends with newline
    if code.ends_with('\n') {
        html.push_str(&format!(
            "<div class=\"line-number\">{}</div>",
            line_count + 1
        ));
    }

    html
}

/// Custom TOML syntax highlighter.
/// Highlights TOML content and returns HTML string with inline styles.
/// Returns content without wrapping pre tag (component provides that).
fn highlight_toml_with_lines(code: &str) -> String {
    let mut html = String::new();

    for line in code.lines() {
        html.push_str(&highlight_toml_line(line));
        html.push('\n');
    }

    // Add trailing newline to match textarea behavior
    // This ensures cursor positioning aligns correctly
    if !code.ends_with('\n') && !code.is_empty() {
        // Remove the last newline we added if original didn't have one
        if html.ends_with('\n') {
            html.pop();
        }
    }

    html
}

/// Highlights a single line of TOML.
fn highlight_toml_line(line: &str) -> String {
    let trimmed = line.trim();

    // Empty line
    if trimmed.is_empty() {
        return escape_html(line);
    }

    // Comment line
    if trimmed.starts_with('#') {
        return format!(
            "<span style=\"color: #65737e;\">{}</span>",
            escape_html(line)
        );
    }

    // Array table header [[...]]
    if trimmed.starts_with("[[") && trimmed.ends_with("]]") {
        return format!(
            "<span style=\"color: #c0c5ce;\">{}</span><span style=\"color: #8fa1b3;\">{}</span><span style=\"color: #c0c5ce;\">{}</span>",
            escape_html(&get_leading_whitespace(line)),
            escape_html(trimmed),
            ""
        );
    }

    // Table header [...]
    if trimmed.starts_with('[') && trimmed.ends_with(']') && !trimmed.starts_with("[[") {
        return format!(
            "<span style=\"color: #c0c5ce;\">{}</span><span style=\"color: #8fa1b3;\">{}</span>",
            escape_html(&get_leading_whitespace(line)),
            escape_html(trimmed)
        );
    }

    // Key-value pair
    if let Some(eq_pos) = find_equals_outside_strings(trimmed) {
        let key_part = &trimmed[..eq_pos];
        let value_part = &trimmed[eq_pos + 1..];

        let leading_ws = get_leading_whitespace(line);
        let highlighted_value = highlight_toml_value(value_part.trim());

        // Handle inline comment after value
        let (value_html, comment_html) =
            if let Some(comment_start) = find_comment_in_value(value_part) {
                let val = &value_part[..comment_start];
                let comment = &value_part[comment_start..];
                (
                    highlight_toml_value(val.trim()),
                    format!(
                        " <span style=\"color: #65737e;\">{}</span>",
                        escape_html(comment.trim())
                    ),
                )
            } else {
                (highlighted_value, String::new())
            };

        return format!(
            "{}<span style=\"color: #bf616a;\">{}</span><span style=\"color: #c0c5ce;\"> = </span>{}{}",
            escape_html(&leading_ws),
            escape_html(key_part.trim()),
            value_html,
            comment_html
        );
    }

    // Default: just escape
    escape_html(line)
}

/// Highlights a TOML value (right side of =).
fn highlight_toml_value(value: &str) -> String {
    let trimmed = value.trim();

    // Boolean
    if trimmed == "true" || trimmed == "false" {
        return format!("<span style=\"color: #d08770;\">{}</span>", trimmed);
    }

    // Number (integer or float)
    if is_toml_number(trimmed) {
        return format!(
            "<span style=\"color: #d08770;\">{}</span>",
            escape_html(trimmed)
        );
    }

    // String (basic "" or literal '')
    if (trimmed.starts_with('"') && trimmed.ends_with('"'))
        || (trimmed.starts_with('\'') && trimmed.ends_with('\''))
        || (trimmed.starts_with("\"\"\""))
        || (trimmed.starts_with("'''"))
    {
        return format!(
            "<span style=\"color: #a3be8c;\">{}</span>",
            escape_html(trimmed)
        );
    }

    // Array
    if trimmed.starts_with('[') {
        return highlight_toml_array(trimmed);
    }

    // Inline table
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        return format!(
            "<span style=\"color: #c0c5ce;\">{}</span>",
            escape_html(trimmed)
        );
    }

    // Default
    escape_html(trimmed)
}

/// Highlights a TOML array.
fn highlight_toml_array(arr: &str) -> String {
    // Simple implementation: just color the brackets and try to color contents
    let mut result = String::new();
    let mut in_string = false;
    let mut string_char = ' ';
    let mut current_token = String::new();

    for ch in arr.chars() {
        if in_string {
            current_token.push(ch);
            if ch == string_char {
                // End of string
                result.push_str(&format!(
                    "<span style=\"color: #a3be8c;\">{}</span>",
                    escape_html(&current_token)
                ));
                current_token.clear();
                in_string = false;
            }
        } else {
            match ch {
                '"' | '\'' => {
                    // Flush current token
                    if !current_token.is_empty() {
                        result.push_str(&highlight_array_token(&current_token));
                        current_token.clear();
                    }
                    in_string = true;
                    string_char = ch;
                    current_token.push(ch);
                }
                '[' | ']' | ',' => {
                    // Flush current token
                    if !current_token.is_empty() {
                        result.push_str(&highlight_array_token(&current_token));
                        current_token.clear();
                    }
                    result.push_str(&format!("<span style=\"color: #c0c5ce;\">{}</span>", ch));
                }
                ' ' => {
                    if !current_token.is_empty() {
                        result.push_str(&highlight_array_token(&current_token));
                        current_token.clear();
                    }
                    result.push(' ');
                }
                _ => {
                    current_token.push(ch);
                }
            }
        }
    }

    // Flush remaining token
    if !current_token.is_empty() {
        if in_string {
            result.push_str(&format!(
                "<span style=\"color: #a3be8c;\">{}</span>",
                escape_html(&current_token)
            ));
        } else {
            result.push_str(&highlight_array_token(&current_token));
        }
    }

    result
}

/// Highlights a token inside an array.
fn highlight_array_token(token: &str) -> String {
    let trimmed = token.trim();
    if trimmed.is_empty() {
        return escape_html(token);
    }

    if trimmed == "true" || trimmed == "false" {
        return format!("<span style=\"color: #d08770;\">{}</span>", trimmed);
    }

    if is_toml_number(trimmed) {
        return format!(
            "<span style=\"color: #d08770;\">{}</span>",
            escape_html(trimmed)
        );
    }

    escape_html(token)
}

/// Checks if a string looks like a TOML number.
fn is_toml_number(s: &str) -> bool {
    let s = s.trim();
    if s.is_empty() {
        return false;
    }

    // Handle special float values
    if s == "inf" || s == "+inf" || s == "-inf" || s == "nan" || s == "+nan" || s == "-nan" {
        return true;
    }

    // Handle hex, octal, binary
    if s.starts_with("0x") || s.starts_with("0o") || s.starts_with("0b") {
        return s[2..].chars().all(|c| c.is_ascii_hexdigit() || c == '_');
    }

    // Regular number (may have underscores, decimal point, exponent)
    let mut has_digit = false;
    let mut chars = s.chars().peekable();

    // Optional sign
    if chars.peek() == Some(&'+') || chars.peek() == Some(&'-') {
        chars.next();
    }

    for ch in chars {
        match ch {
            '0'..='9' => has_digit = true,
            '_' | '.' | 'e' | 'E' | '+' | '-' => {}
            _ => return false,
        }
    }

    has_digit
}

/// Finds the position of '=' outside of strings.
fn find_equals_outside_strings(s: &str) -> Option<usize> {
    let mut in_string = false;
    let mut string_char = ' ';

    for (i, ch) in s.char_indices() {
        if in_string {
            if ch == string_char {
                in_string = false;
            }
        } else {
            match ch {
                '"' | '\'' => {
                    in_string = true;
                    string_char = ch;
                }
                '=' => return Some(i),
                _ => {}
            }
        }
    }

    None
}

/// Finds comment start position in a value part (after =).
fn find_comment_in_value(s: &str) -> Option<usize> {
    let mut in_string = false;
    let mut string_char = ' ';

    for (i, ch) in s.char_indices() {
        if in_string {
            if ch == string_char {
                in_string = false;
            }
        } else {
            match ch {
                '"' | '\'' => {
                    in_string = true;
                    string_char = ch;
                }
                '#' => return Some(i),
                _ => {}
            }
        }
    }

    None
}

/// Gets leading whitespace from a line.
fn get_leading_whitespace(s: &str) -> String {
    s.chars().take_while(|c| c.is_whitespace()).collect()
}

/// Escapes HTML special characters.
fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
