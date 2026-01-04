# Markdown Renderer

A utility package for rendering markdown content with beautiful terminal styling using [Glamour](https://github.com/charmbracelet/glamour).

## Features

- **Smart TTY Detection**: Automatically detects if output is a terminal or pipe
- **Beautiful Rendering**: Uses Glamour for Glow-style markdown rendering
- **NO_COLOR Support**: Respects the `NO_COLOR` environment variable
- **Graceful Fallback**: Returns plain markdown when rendering fails
- **Configurable**: Supports custom width, styles, and color options

## Usage

### Quick Start

```go
import "github.com/finos/morphir/pkg/tooling/markdown"

// Simple rendering with auto-detection
content := "# Hello World\n\nThis is **bold** text."
rendered, err := markdown.RenderMarkdown(content)
if err != nil {
    // Handle error
}
fmt.Print(rendered)
```

### Render to Writer

```go
// Render and write to a specific writer
err := markdown.RenderMarkdownToWriter(content, os.Stdout)
```

### Custom Options

```go
renderer := markdown.NewRenderer(markdown.RenderOptions{
    Width:      80,        // Word wrap width
    NoColor:    false,     // Disable coloring
    ForceColor: false,     // Force color even in non-TTY
    Style:      "",        // Custom glamour style
})

rendered, err := renderer.RenderString(content)
```

## Behavior

### Terminal Output

When outputting to a terminal (TTY), the renderer applies beautiful styling:

```bash
$ morphir validate --report markdown
# Renders with colors, formatting, and syntax highlighting
```

### Piped Output

When output is piped or redirected, plain markdown is returned:

```bash
$ morphir validate --report markdown | less
# Returns plain markdown for pagers

$ morphir validate --report markdown > report.md
# Saves plain markdown to file
```

### NO_COLOR Support

Respects the `NO_COLOR` environment variable:

```bash
$ NO_COLOR=1 morphir validate --report markdown
# Outputs plain markdown even in terminal
```

## Integration Example

### In Validate Command

```go
func outputValidationReport(cmd *cobra.Command, result *validation.Result) error {
    gen := report.NewGenerator(report.FormatMarkdown)
    reportContent := gen.Generate(result)

    // Render with glamour (auto-detects TTY)
    renderer := markdown.DefaultRenderer()
    rendered, err := renderer.Render(reportContent, cmd.OutOrStdout())
    if err != nil {
        // Fallback to plain markdown
        fmt.Fprint(cmd.OutOrStdout(), reportContent)
    } else {
        fmt.Fprint(cmd.OutOrStdout(), rendered)
    }

    return nil
}
```

## Testing

The package includes comprehensive tests for:

- TTY detection
- NO_COLOR environment variable handling
- Custom options (width, colors)
- Error handling and fallback behavior

```bash
cd pkg/tooling
go test ./markdown/...
```

## Dependencies

- `github.com/charmbracelet/glamour` - Markdown rendering engine
- `github.com/mattn/go-isatty` - Terminal detection

## Design Goals

1. **Zero Configuration**: Works out of the box with sensible defaults
2. **Fail Safe**: Always falls back to plain markdown on errors
3. **Standards Compliant**: Respects `NO_COLOR` convention
4. **Composable**: Easy to integrate into any CLI tool

## Related

- [Glamour](https://github.com/charmbracelet/glamour) - The rendering engine
- [Glow](https://github.com/charmbracelet/glow) - CLI markdown viewer
- [NO_COLOR](https://no-color.org/) - Standard for disabling color output
