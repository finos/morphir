// Package markdown provides utilities for rendering markdown content with terminal styling.
package markdown

import (
	"io"
	"os"

	"github.com/charmbracelet/glamour"
	"github.com/mattn/go-isatty"
)

// RenderOptions configures markdown rendering behavior.
type RenderOptions struct {
	// Width specifies the word wrap width. If 0, uses terminal width or 80.
	Width int

	// ForceColor forces colored output even when not in a TTY.
	ForceColor bool

	// NoColor disables all styling and outputs plain text.
	NoColor bool

	// Style specifies the glamour style to use. If empty, uses auto-detection.
	Style string
}

// Renderer provides markdown rendering with terminal detection.
type Renderer struct {
	opts RenderOptions
}

// NewRenderer creates a new markdown renderer with the given options.
func NewRenderer(opts RenderOptions) *Renderer {
	return &Renderer{opts: opts}
}

// DefaultRenderer creates a renderer with sensible defaults.
func DefaultRenderer() *Renderer {
	return &Renderer{
		opts: RenderOptions{
			Width: 0, // Auto-detect
		},
	}
}

// Render renders markdown content with appropriate styling based on output destination.
// If outputting to a terminal, renders with glamour styling.
// If piped or redirected, returns raw markdown.
func (r *Renderer) Render(content string, w io.Writer) (string, error) {
	// Check if we should render with styling
	if !r.shouldRender(w) {
		return content, nil
	}

	// Create glamour renderer
	termRenderer, err := r.createGlamourRenderer()
	if err != nil {
		// Fallback to plain text on error
		return content, nil
	}

	// Render the markdown
	rendered, err := termRenderer.Render(content)
	if err != nil {
		// Fallback to plain text on render error
		return content, nil
	}

	return rendered, nil
}

// RenderString is a convenience method that renders to a string.
func (r *Renderer) RenderString(content string) (string, error) {
	return r.Render(content, os.Stdout)
}

// shouldRender determines if we should apply styling based on output destination and options.
func (r *Renderer) shouldRender(w io.Writer) bool {
	// Respect NO_COLOR environment variable
	if os.Getenv("NO_COLOR") != "" && !r.opts.ForceColor {
		return false
	}

	// Respect NoColor option
	if r.opts.NoColor {
		return false
	}

	// Force color if requested
	if r.opts.ForceColor {
		return true
	}

	// Check if output is a terminal
	if f, ok := w.(*os.File); ok {
		return isatty.IsTerminal(f.Fd()) || isatty.IsCygwinTerminal(f.Fd())
	}

	return false
}

// createGlamourRenderer creates a glamour TermRenderer with appropriate settings.
func (r *Renderer) createGlamourRenderer() (*glamour.TermRenderer, error) {
	width := r.opts.Width
	if width == 0 {
		width = getTerminalWidth()
	}

	// Determine style
	style := r.opts.Style
	if style == "" {
		// Use auto-detection for dark/light mode
		return glamour.NewTermRenderer(
			glamour.WithAutoStyle(),
			glamour.WithWordWrap(width),
		)
	}

	// Use specified style
	return glamour.NewTermRenderer(
		glamour.WithStylePath(style),
		glamour.WithWordWrap(width),
	)
}

// getTerminalWidth returns the current terminal width or a sensible default.
func getTerminalWidth() int {
	// Try to get terminal size
	// This is a simple implementation; glamour has its own logic for this
	// We'll use a sensible default and let glamour handle it
	return 80
}

// RenderToWriter renders markdown and writes directly to the writer.
func (r *Renderer) RenderToWriter(content string, w io.Writer) error {
	rendered, err := r.Render(content, w)
	if err != nil {
		return err
	}

	_, err = w.Write([]byte(rendered))
	return err
}

// Quick render functions for convenience

// RenderMarkdown renders markdown with default settings.
// Auto-detects terminal and applies styling when appropriate.
func RenderMarkdown(content string) (string, error) {
	return DefaultRenderer().RenderString(content)
}

// RenderMarkdownToWriter renders markdown and writes to the given writer.
func RenderMarkdownToWriter(content string, w io.Writer) error {
	return DefaultRenderer().RenderToWriter(content, w)
}

// IsTerminal checks if the given writer is a terminal.
func IsTerminal(w io.Writer) bool {
	if f, ok := w.(*os.File); ok {
		return isatty.IsTerminal(f.Fd()) || isatty.IsCygwinTerminal(f.Fd())
	}
	return false
}
