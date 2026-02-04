//! JSON pager with syntax highlighting and scrolling.
//!
//! Provides a full-screen TUI for viewing JSON content with:
//! - Syntax highlighting
//! - Line numbers
//! - Keyboard navigation (arrows, page up/down, home/end)
//! - Vim-like visual mode selection (v for character, V for line)
//! - Yank (copy) with y
//! - Quit with 'q'

use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Frame, Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Scrollbar, ScrollbarOrientation, ScrollbarState},
};
use std::io::{self, Stdout};
use syntect::easy::HighlightLines;
use syntect::highlighting::{FontStyle, ThemeSet};
use syntect::parsing::SyntaxSet;

/// Visual mode type (like vim)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VisualMode {
    /// Not in visual mode
    None,
    /// Character-wise visual mode (v)
    Character,
    /// Line-wise visual mode (V)
    Line,
}

/// Cursor position in the content
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CursorPos {
    line: usize,
    col: usize,
}

/// A JSON pager with syntax highlighting and scrolling.
pub struct JsonPager {
    /// The JSON content to display
    content: String,
    /// Raw lines for selection/copying
    raw_lines: Vec<String>,
    /// Title shown in the header
    title: String,
    /// Current scroll position (line offset)
    scroll: usize,
    /// Parsed and highlighted lines
    lines: Vec<Vec<(Style, String)>>,
    /// Total number of lines
    line_count: usize,
    /// Current visual mode
    visual_mode: VisualMode,
    /// Current cursor position
    cursor: CursorPos,
    /// Selection start position (when in visual mode)
    selection_start: CursorPos,
    /// Status message to display temporarily
    status_message: Option<String>,
}

impl JsonPager {
    /// Create a new JSON pager with the given content and title.
    pub fn new(content: String, title: String) -> Self {
        let lines = Self::highlight_json(&content);
        let line_count = lines.len();
        let raw_lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
        Self {
            content,
            raw_lines,
            title,
            scroll: 0,
            lines,
            line_count,
            visual_mode: VisualMode::None,
            cursor: CursorPos { line: 0, col: 0 },
            selection_start: CursorPos { line: 0, col: 0 },
            status_message: None,
        }
    }

    /// Parse and highlight JSON content into styled lines.
    fn highlight_json(content: &str) -> Vec<Vec<(Style, String)>> {
        let ps = SyntaxSet::load_defaults_newlines();
        let ts = ThemeSet::load_defaults();
        let theme = &ts.themes["base16-ocean.dark"];
        let syntax = ps.find_syntax_by_extension("json").unwrap();
        let mut h = HighlightLines::new(syntax, theme);

        content
            .lines()
            .map(|line| {
                let line_with_newline = format!("{}\n", line);
                let ranges = h.highlight_line(&line_with_newline, &ps).unwrap();

                ranges
                    .into_iter()
                    .map(|(style, text)| {
                        let fg =
                            Color::Rgb(style.foreground.r, style.foreground.g, style.foreground.b);
                        let mut ratatui_style = Style::default().fg(fg);
                        if style.font_style.contains(FontStyle::BOLD) {
                            ratatui_style = ratatui_style.add_modifier(Modifier::BOLD);
                        }
                        if style.font_style.contains(FontStyle::ITALIC) {
                            ratatui_style = ratatui_style.add_modifier(Modifier::ITALIC);
                        }
                        (ratatui_style, text.trim_end_matches('\n').to_string())
                    })
                    .collect()
            })
            .collect()
    }

    /// Run the pager in the terminal.
    pub fn run(mut self) -> io::Result<()> {
        // Check if stdout is a terminal
        if !std::io::stdout().is_terminal() {
            // Fall back to simple output
            self.print_simple();
            return Ok(());
        }

        // Setup terminal
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
        let backend = CrosstermBackend::new(stdout);
        let mut terminal = Terminal::new(backend)?;

        // Run the event loop
        let result = self.run_loop(&mut terminal);

        // Restore terminal
        disable_raw_mode()?;
        execute!(
            terminal.backend_mut(),
            LeaveAlternateScreen,
            DisableMouseCapture
        )?;
        terminal.show_cursor()?;

        result
    }

    /// Print simple output for non-TTY contexts.
    fn print_simple(&self) {
        let width = self.line_count.to_string().len().max(3);
        let gutter_width = width + 1;
        let gutter_fill: String = "─".repeat(gutter_width);
        let border_color = "\x1b[38;5;238m";
        let reset = "\x1b[0m";

        // Top border
        print!("{}{}┬", border_color, gutter_fill);
        println!("{}{}", "─".repeat(60), reset);

        // Header
        println!(
            "{}{:>gutter_width$}│{} \x1b[1mFile: {}\x1b[0m",
            border_color, " ", reset, self.title
        );

        // Separator
        print!("{}{}┼", border_color, gutter_fill);
        println!("{}{}", "─".repeat(60), reset);

        // Content with line numbers
        for (i, line) in self.content.lines().enumerate() {
            print!(
                "\x1b[38;5;243m{:>width$}\x1b[0m {}│{} ",
                i + 1,
                border_color,
                reset,
                width = width
            );
            println!("{}", line);
        }

        // Bottom border
        print!("{}{}┴", border_color, gutter_fill);
        println!("{}{}", "─".repeat(60), reset);
    }

    /// Main event loop.
    fn run_loop(&mut self, terminal: &mut Terminal<CrosstermBackend<Stdout>>) -> io::Result<()> {
        let visible_height = terminal.size()?.height.saturating_sub(4) as usize;

        loop {
            terminal.draw(|f| self.render(f))?;

            if let Event::Key(key) = event::read()? {
                // Clear status message on any key
                self.status_message = None;

                match key.code {
                    // Quit (q only exits visual mode if active, Esc always exits)
                    KeyCode::Char('q') => {
                        if self.visual_mode != VisualMode::None {
                            self.visual_mode = VisualMode::None;
                        } else {
                            break;
                        }
                    }
                    KeyCode::Esc => {
                        if self.visual_mode != VisualMode::None {
                            self.visual_mode = VisualMode::None;
                        } else {
                            break;
                        }
                    }
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => break,

                    // Visual mode activation
                    KeyCode::Char('v') => {
                        if self.visual_mode == VisualMode::Character {
                            self.visual_mode = VisualMode::None;
                        } else {
                            self.visual_mode = VisualMode::Character;
                            self.selection_start = self.cursor;
                        }
                    }
                    KeyCode::Char('V') => {
                        if self.visual_mode == VisualMode::Line {
                            self.visual_mode = VisualMode::None;
                        } else {
                            self.visual_mode = VisualMode::Line;
                            self.selection_start = self.cursor;
                        }
                    }

                    // Yank (copy) selection
                    KeyCode::Char('y') => {
                        if self.visual_mode != VisualMode::None {
                            // Move cursor to start of selection (like vim)
                            let (start, _) = self.get_selection_bounds();
                            self.yank_selection();
                            self.cursor = start;
                            self.visual_mode = VisualMode::None;
                        }
                    }

                    // Movement keys (work in both normal and visual mode)
                    KeyCode::Down | KeyCode::Char('j') => {
                        self.move_cursor_down(1, visible_height);
                    }
                    KeyCode::Up | KeyCode::Char('k') => {
                        self.move_cursor_up(1, visible_height);
                    }
                    KeyCode::Right | KeyCode::Char('l') => {
                        self.move_cursor_right();
                    }
                    KeyCode::Left | KeyCode::Char('h') => {
                        self.move_cursor_left();
                    }
                    KeyCode::PageDown | KeyCode::Char(' ') => {
                        self.move_cursor_down(visible_height, visible_height);
                    }
                    KeyCode::PageUp => {
                        self.move_cursor_up(visible_height, visible_height);
                    }
                    KeyCode::Home | KeyCode::Char('g') => {
                        self.cursor.line = 0;
                        self.cursor.col = 0;
                        self.scroll = 0;
                    }
                    KeyCode::End | KeyCode::Char('G') => {
                        self.cursor.line = self.line_count.saturating_sub(1);
                        self.cursor.col = 0;
                        self.scroll = self.line_count.saturating_sub(visible_height);
                    }
                    KeyCode::Char('0') => {
                        self.cursor.col = 0;
                    }
                    KeyCode::Char('$') => {
                        if let Some(line) = self.raw_lines.get(self.cursor.line) {
                            self.cursor.col = line.len().saturating_sub(1);
                        }
                    }
                    KeyCode::Char('w') => {
                        self.move_word_forward();
                    }
                    KeyCode::Char('b') => {
                        self.move_word_backward();
                    }
                    _ => {}
                }
            }
        }
        Ok(())
    }

    /// Move cursor down by given lines, adjusting scroll as needed.
    fn move_cursor_down(&mut self, lines: usize, visible_height: usize) {
        self.cursor.line = (self.cursor.line + lines).min(self.line_count.saturating_sub(1));
        // Clamp column to line length
        if let Some(line) = self.raw_lines.get(self.cursor.line) {
            self.cursor.col = self.cursor.col.min(line.len().saturating_sub(1).max(0));
        }
        // Scroll to keep cursor visible
        if self.cursor.line >= self.scroll + visible_height {
            self.scroll = self.cursor.line.saturating_sub(visible_height) + 1;
        }
    }

    /// Move cursor up by given lines, adjusting scroll as needed.
    fn move_cursor_up(&mut self, lines: usize, visible_height: usize) {
        self.cursor.line = self.cursor.line.saturating_sub(lines);
        // Clamp column to line length
        if let Some(line) = self.raw_lines.get(self.cursor.line) {
            self.cursor.col = self.cursor.col.min(line.len().saturating_sub(1).max(0));
        }
        // Scroll to keep cursor visible
        if self.cursor.line < self.scroll {
            self.scroll = self.cursor.line;
        }
        let _ = visible_height; // Suppress unused warning
    }

    /// Move cursor right within the current line.
    fn move_cursor_right(&mut self) {
        if let Some(line) = self.raw_lines.get(self.cursor.line)
            && self.cursor.col < line.len().saturating_sub(1)
        {
            self.cursor.col += 1;
        }
    }

    /// Move cursor left within the current line.
    fn move_cursor_left(&mut self) {
        self.cursor.col = self.cursor.col.saturating_sub(1);
    }

    /// Move cursor forward by one word.
    fn move_word_forward(&mut self) {
        if let Some(line) = self.raw_lines.get(self.cursor.line) {
            let chars: Vec<char> = line.chars().collect();
            let mut col = self.cursor.col;
            // Skip current word
            while col < chars.len() && !chars[col].is_whitespace() {
                col += 1;
            }
            // Skip whitespace
            while col < chars.len() && chars[col].is_whitespace() {
                col += 1;
            }
            if col >= chars.len() && self.cursor.line + 1 < self.line_count {
                // Move to next line
                self.cursor.line += 1;
                self.cursor.col = 0;
            } else {
                self.cursor.col = col.min(chars.len().saturating_sub(1));
            }
        }
    }

    /// Move cursor backward by one word.
    fn move_word_backward(&mut self) {
        if let Some(line) = self.raw_lines.get(self.cursor.line) {
            let chars: Vec<char> = line.chars().collect();
            let mut col = self.cursor.col;
            if col == 0 && self.cursor.line > 0 {
                // Move to end of previous line
                self.cursor.line -= 1;
                if let Some(prev_line) = self.raw_lines.get(self.cursor.line) {
                    self.cursor.col = prev_line.len().saturating_sub(1);
                }
                return;
            }
            // Skip whitespace before
            while col > 0
                && chars
                    .get(col.saturating_sub(1))
                    .is_some_and(|c| c.is_whitespace())
            {
                col = col.saturating_sub(1);
            }
            // Skip to beginning of word
            while col > 0
                && chars
                    .get(col.saturating_sub(1))
                    .is_some_and(|c| !c.is_whitespace())
            {
                col = col.saturating_sub(1);
            }
            self.cursor.col = col;
        }
    }

    /// Yank (copy) the current selection to clipboard.
    fn yank_selection(&mut self) {
        let text = self.get_selected_text();
        if text.is_empty() {
            return;
        }

        // Try to copy to clipboard using available methods
        let copied = self.copy_to_clipboard(&text);

        if copied {
            let line_count = text.lines().count();
            self.status_message = Some(format!("{} line(s) yanked", line_count));
        } else {
            self.status_message = Some("Yank failed: no clipboard available".to_string());
        }
    }

    /// Get the currently selected text.
    fn get_selected_text(&self) -> String {
        if self.visual_mode == VisualMode::None {
            return String::new();
        }

        let (start, end) = self.get_selection_bounds();

        match self.visual_mode {
            VisualMode::Line => {
                // Line-wise: select entire lines
                self.raw_lines[start.line..=end.line].join("\n")
            }
            VisualMode::Character => {
                // Character-wise selection
                if start.line == end.line {
                    // Single line selection
                    if let Some(line) = self.raw_lines.get(start.line) {
                        let chars: Vec<char> = line.chars().collect();
                        let start_col = start.col.min(chars.len());
                        let end_col = (end.col + 1).min(chars.len());
                        chars[start_col..end_col].iter().collect()
                    } else {
                        String::new()
                    }
                } else {
                    // Multi-line selection
                    let mut result = String::new();
                    for line_idx in start.line..=end.line {
                        if let Some(line) = self.raw_lines.get(line_idx) {
                            let chars: Vec<char> = line.chars().collect();
                            if line_idx == start.line {
                                let start_col = start.col.min(chars.len());
                                result.push_str(&chars[start_col..].iter().collect::<String>());
                            } else if line_idx == end.line {
                                let end_col = (end.col + 1).min(chars.len());
                                result.push_str(&chars[..end_col].iter().collect::<String>());
                            } else {
                                result.push_str(line);
                            }
                        }
                        if line_idx < end.line {
                            result.push('\n');
                        }
                    }
                    result
                }
            }
            VisualMode::None => String::new(),
        }
    }

    /// Get selection bounds (start, end) ordered correctly.
    fn get_selection_bounds(&self) -> (CursorPos, CursorPos) {
        let a = self.selection_start;
        let b = self.cursor;

        if a.line < b.line || (a.line == b.line && a.col <= b.col) {
            (a, b)
        } else {
            (b, a)
        }
    }

    /// Check if a position is within the current selection.
    fn is_in_selection(&self, line: usize, col: usize) -> bool {
        if self.visual_mode == VisualMode::None {
            return false;
        }

        let (start, end) = self.get_selection_bounds();

        match self.visual_mode {
            VisualMode::Line => line >= start.line && line <= end.line,
            VisualMode::Character => {
                if line < start.line || line > end.line {
                    false
                } else if start.line == end.line {
                    col >= start.col && col <= end.col
                } else if line == start.line {
                    col >= start.col
                } else if line == end.line {
                    col <= end.col
                } else {
                    true
                }
            }
            VisualMode::None => false,
        }
    }

    /// Copy text to clipboard using available system tools.
    fn copy_to_clipboard(&self, text: &str) -> bool {
        use std::io::Write;
        use std::process::{Command, Stdio};

        // Helper to try a clipboard command with timeout
        let try_clipboard = |cmd: &str, args: &[&str]| -> bool {
            if let Ok(mut child) = Command::new(cmd)
                .args(args)
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                && let Some(mut stdin) = child.stdin.take()
                && stdin.write_all(text.as_bytes()).is_ok()
            {
                drop(stdin); // Close stdin before waiting
                // Use wait_with_output with a timeout approach
                // For simplicity, just wait - the command should complete quickly
                return child.wait().is_ok_and(|s| s.success());
            }
            false
        };

        #[cfg(target_os = "macos")]
        {
            if try_clipboard("pbcopy", &[]) {
                return true;
            }
        }

        #[cfg(target_os = "linux")]
        {
            // Check if we're in WSL by looking for Windows interop
            let is_wsl = std::path::Path::new("/proc/sys/fs/binfmt_misc/WSLInterop").exists()
                || std::env::var("WSL_DISTRO_NAME").is_ok();

            if is_wsl {
                // WSL: Use Windows clipboard via clip.exe
                if try_clipboard("clip.exe", &[]) {
                    return true;
                }
                // Try win32yank if available (common WSL clipboard tool)
                if try_clipboard("win32yank.exe", &["-i", "--crlf"]) {
                    return true;
                }
            }

            // Try wl-copy for Wayland
            if try_clipboard("wl-copy", &[]) {
                return true;
            }

            // Try xclip/xsel only if DISPLAY is set (X11 available)
            if std::env::var("DISPLAY").is_ok() {
                if try_clipboard("xclip", &["-selection", "clipboard"]) {
                    return true;
                }
                if try_clipboard("xsel", &["--clipboard", "--input"]) {
                    return true;
                }
            }
        }

        #[cfg(target_os = "windows")]
        {
            if try_clipboard("clip", &[]) {
                return true;
            }
        }

        false
    }

    /// Render the pager UI.
    fn render(&self, frame: &mut Frame) {
        let area = frame.area();

        // Layout: header (1 line), content, footer (1 line)
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // Header
                Constraint::Min(1),    // Content
                Constraint::Length(1), // Footer
            ])
            .split(area);

        self.render_header(frame, chunks[0]);
        self.render_content(frame, chunks[1]);
        self.render_footer(frame, chunks[2]);
    }

    /// Render the header bar.
    fn render_header(&self, frame: &mut Frame, area: Rect) {
        let header = Paragraph::new(format!(" File: {}", self.title)).style(
            Style::default()
                .bg(Color::DarkGray)
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        );
        frame.render_widget(header, area);
    }

    /// Render the content area with line numbers and syntax highlighting.
    fn render_content(&self, frame: &mut Frame, area: Rect) {
        let line_num_width = self.line_count.to_string().len().max(3);
        let _content_width = area.width.saturating_sub(line_num_width as u16 + 3) as usize; // +3 for " │ "

        // Selection highlight style
        let selection_style = Style::default()
            .bg(Color::Indexed(236))
            .add_modifier(Modifier::REVERSED);

        // Build visible lines
        let visible_height = area.height as usize;
        let mut text_lines: Vec<Line> = Vec::new();

        for i in 0..visible_height {
            let line_idx = self.scroll + i;
            if line_idx >= self.line_count {
                // Empty line padding
                text_lines.push(Line::from(vec![
                    Span::styled(
                        format!("{:>width$}", "~", width = line_num_width),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::styled(" │ ", Style::default().fg(Color::DarkGray)),
                ]));
            } else {
                // Determine line number style based on cursor position
                let line_num_style = if line_idx == self.cursor.line {
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::Indexed(243))
                };

                // Line number
                let mut spans = vec![
                    Span::styled(
                        format!("{:>width$}", line_idx + 1, width = line_num_width),
                        line_num_style,
                    ),
                    Span::styled(" │ ", Style::default().fg(Color::DarkGray)),
                ];

                // Get the raw line for character-level rendering
                if let Some(raw_line) = self.raw_lines.get(line_idx) {
                    // For visual mode, we need to render character by character
                    if self.visual_mode != VisualMode::None {
                        let chars: Vec<char> = raw_line.chars().collect();
                        let mut col = 0;

                        // Build spans with selection highlighting
                        for styled_segment in self.lines.get(line_idx).unwrap_or(&Vec::new()) {
                            let (base_style, text) = styled_segment;
                            for ch in text.chars() {
                                let is_cursor =
                                    line_idx == self.cursor.line && col == self.cursor.col;
                                let is_selected = self.is_in_selection(line_idx, col);

                                let style = if is_cursor {
                                    base_style.bg(Color::White).fg(Color::Black)
                                } else if is_selected {
                                    base_style.patch(selection_style)
                                } else {
                                    *base_style
                                };

                                spans.push(Span::styled(ch.to_string(), style));
                                col += 1;
                            }
                        }

                        // Handle empty lines - show cursor
                        if chars.is_empty() && line_idx == self.cursor.line {
                            spans.push(Span::styled(
                                " ",
                                Style::default().bg(Color::White).fg(Color::Black),
                            ));
                        }
                    } else {
                        // Normal mode rendering with cursor
                        let chars: Vec<char> = raw_line.chars().collect();
                        let mut col = 0;

                        for styled_segment in self.lines.get(line_idx).unwrap_or(&Vec::new()) {
                            let (base_style, text) = styled_segment;
                            for ch in text.chars() {
                                let is_cursor =
                                    line_idx == self.cursor.line && col == self.cursor.col;
                                let style = if is_cursor {
                                    base_style.bg(Color::White).fg(Color::Black)
                                } else {
                                    *base_style
                                };
                                spans.push(Span::styled(ch.to_string(), style));
                                col += 1;
                            }
                        }

                        // Handle empty lines or cursor past end of line
                        if line_idx == self.cursor.line && col <= self.cursor.col {
                            spans.push(Span::styled(
                                " ",
                                Style::default().bg(Color::White).fg(Color::Black),
                            ));
                        }

                        let _ = chars; // Suppress unused warning
                    }
                }

                text_lines.push(Line::from(spans));
            }
        }

        let content = Paragraph::new(text_lines)
            .block(Block::default().borders(Borders::LEFT | Borders::RIGHT));

        // Scrollbar
        let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
            .begin_symbol(Some("↑"))
            .end_symbol(Some("↓"));

        let mut scrollbar_state = ScrollbarState::new(self.line_count)
            .position(self.scroll)
            .viewport_content_length(visible_height);

        frame.render_widget(content, area);
        frame.render_stateful_widget(
            scrollbar,
            area.inner(ratatui::layout::Margin {
                vertical: 0,
                horizontal: 0,
            }),
            &mut scrollbar_state,
        );
    }

    /// Render the footer bar with help text.
    fn render_footer(&self, frame: &mut Frame, area: Rect) {
        let progress = if self.line_count > 0 {
            let percent = ((self.cursor.line + 1) * 100) / self.line_count;
            format!("{}%", percent.min(100))
        } else {
            "0%".to_string()
        };

        // Build footer text based on current mode
        let (mode_text, help_text) = match self.visual_mode {
            VisualMode::None => ("", " hjkl: move  v/V: visual  g/G: top/bottom  q: quit"),
            VisualMode::Character => ("-- VISUAL --", " hjkl: select  y: yank  Esc: cancel"),
            VisualMode::Line => ("-- VISUAL LINE --", " jk: select  y: yank  Esc: cancel"),
        };

        // Check for status message
        let status = if let Some(msg) = &self.status_message {
            format!(" {}", msg)
        } else {
            String::new()
        };

        let position_info = format!(
            "{}:{} ({}/{})",
            self.cursor.line + 1,
            self.cursor.col + 1,
            self.cursor.line + 1,
            self.line_count
        );

        let footer_text = if !mode_text.is_empty() {
            format!(
                " {}{}  {} │ {} ({})",
                mode_text, status, help_text, position_info, progress
            )
        } else {
            format!(
                "{}{}  {} │ {} ({})",
                help_text, status, "", position_info, progress
            )
        };

        let footer_style = match self.visual_mode {
            VisualMode::None => Style::default().bg(Color::DarkGray).fg(Color::White),
            _ => Style::default()
                .bg(Color::Indexed(236))
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        };

        let footer = Paragraph::new(footer_text).style(footer_style);
        frame.render_widget(footer, area);
    }
}

use std::io::IsTerminal;
