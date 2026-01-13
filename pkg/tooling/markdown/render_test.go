package markdown_test

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/finos/morphir/pkg/tooling/markdown"
)

func TestDefaultRenderer(t *testing.T) {
	renderer := markdown.DefaultRenderer()
	if renderer == nil {
		t.Fatal("DefaultRenderer() returned nil")
	}
}

func TestRenderMarkdown_PlainText(t *testing.T) {
	content := "# Hello World\n\nThis is **bold** text."

	// Render with NO_COLOR set
	_ = os.Setenv("NO_COLOR", "1")
	defer func() { _ = os.Unsetenv("NO_COLOR") }()

	rendered, err := markdown.RenderMarkdown(content)
	if err != nil {
		t.Fatalf("RenderMarkdown() error = %v", err)
	}

	// When NO_COLOR is set, should return plain markdown
	if rendered != content {
		t.Errorf("Expected plain markdown with NO_COLOR, got rendered output")
	}
}

func TestRenderMarkdownToWriter(t *testing.T) {
	content := "# Test\n\nSome content."
	buf := &bytes.Buffer{}

	err := markdown.RenderMarkdownToWriter(content, buf)
	if err != nil {
		t.Fatalf("RenderMarkdownToWriter() error = %v", err)
	}

	if buf.Len() == 0 {
		t.Error("RenderMarkdownToWriter() wrote no output")
	}
}

func TestRendererOptions_NoColor(t *testing.T) {
	renderer := markdown.NewRenderer(markdown.RenderOptions{
		NoColor: true,
	})

	content := "# Hello\n\n**Bold** text"
	var buf bytes.Buffer

	rendered, err := renderer.Render(content, &buf)
	if err != nil {
		t.Fatalf("Render() error = %v", err)
	}

	// Should return plain text when NoColor is true
	if rendered != content {
		t.Errorf("Expected plain markdown with NoColor option, got rendered output")
	}
}

func TestRendererOptions_Width(t *testing.T) {
	renderer := markdown.NewRenderer(markdown.RenderOptions{
		Width: 40,
	})

	content := strings.Repeat("word ", 100) // Long line that will wrap

	var buf bytes.Buffer
	_, err := renderer.Render(content, &buf)
	if err != nil {
		t.Fatalf("Render() error = %v", err)
	}

	// Just verify no error occurred with custom width
}

func TestIsTerminal(t *testing.T) {
	// Test with stdout
	isStdoutTTY := markdown.IsTerminal(os.Stdout)
	t.Logf("os.Stdout is terminal: %v", isStdoutTTY)

	// Test with a buffer (not a terminal)
	buf := &bytes.Buffer{}
	if markdown.IsTerminal(buf) {
		t.Error("Buffer should not be detected as terminal")
	}

	// Test with a file (not a terminal when running tests)
	file, err := os.CreateTemp("", "test")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Remove(file.Name()) }()
	defer func() { _ = file.Close() }()

	if markdown.IsTerminal(file) {
		t.Error("Regular file should not be detected as terminal")
	}
}

func TestRenderOptions_ForceColor(t *testing.T) {
	// Set NO_COLOR but override with ForceColor
	_ = os.Setenv("NO_COLOR", "1")
	defer func() { _ = os.Unsetenv("NO_COLOR") }()

	renderer := markdown.NewRenderer(markdown.RenderOptions{
		ForceColor: true,
		Width:      80,
	})

	content := "# Test\n\n**Bold** text"
	var buf bytes.Buffer

	_, err := renderer.Render(content, &buf)
	if err != nil {
		t.Fatalf("Render() with ForceColor error = %v", err)
	}

	// When ForceColor is true, should attempt rendering even with NO_COLOR
	// (though the actual rendering will depend on glamour's behavior)
}
