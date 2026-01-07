package json

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// EncodeOptions configures notebook encoding.
type EncodeOptions struct {
	// Indent is the indentation string. Default is single space.
	Indent string
	// SortKeys determines whether to sort object keys.
	SortKeys bool
	// TrailingNewline adds a newline at the end of the output.
	TrailingNewline bool
}

// DefaultEncodeOptions returns the default encoding options matching Jupyter's output.
func DefaultEncodeOptions() EncodeOptions {
	return EncodeOptions{
		Indent:          " ",
		SortKeys:        false,
		TrailingNewline: true,
	}
}

// EncodeNotebook encodes a notebook to JSON bytes.
func EncodeNotebook(nb *NotebookJSON, opts EncodeOptions) ([]byte, error) {
	var buf bytes.Buffer
	if err := EncodeNotebookToWriter(nb, &buf, opts); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// EncodeNotebookToWriter encodes a notebook to a writer.
func EncodeNotebookToWriter(nb *NotebookJSON, w io.Writer, opts EncodeOptions) error {
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	if opts.Indent != "" {
		encoder.SetIndent("", opts.Indent)
	}

	if err := encoder.Encode(nb); err != nil {
		return fmt.Errorf("failed to encode notebook: %w", err)
	}

	// Note: json.Encoder.Encode already adds a trailing newline
	return nil
}

// EncodeCell encodes a cell to JSON bytes.
func EncodeCell(cell *CellJSON, opts EncodeOptions) ([]byte, error) {
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if opts.Indent != "" {
		encoder.SetIndent("", opts.Indent)
	}

	if err := encoder.Encode(cell); err != nil {
		return nil, fmt.Errorf("failed to encode cell: %w", err)
	}

	return buf.Bytes(), nil
}

// EncodeOutput encodes an output to JSON bytes.
func EncodeOutput(output *OutputJSON, opts EncodeOptions) ([]byte, error) {
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if opts.Indent != "" {
		encoder.SetIndent("", opts.Indent)
	}

	if err := encoder.Encode(output); err != nil {
		return nil, fmt.Errorf("failed to encode output: %w", err)
	}

	return buf.Bytes(), nil
}

// FormatMimeBundle converts a map for JSON output, splitting strings into lines
// for text-based MIME types.
func FormatMimeBundle(data map[string]any) map[string]any {
	if data == nil {
		return nil
	}
	result := make(map[string]any, len(data))
	for k, v := range data {
		result[k] = formatMimeValue(k, v)
	}
	return result
}

// formatMimeValue formats a MIME value for JSON output.
func formatMimeValue(mimeType string, v any) any {
	// Text-based types should be split into lines
	if isTextMimeType(mimeType) {
		if s, ok := v.(string); ok {
			return splitLines(s)
		}
	}
	return v
}

// isTextMimeType returns true for MIME types that should be stored as line arrays.
func isTextMimeType(mimeType string) bool {
	switch mimeType {
	case "text/plain", "text/html", "text/latex", "text/markdown",
		"application/javascript", "application/json":
		return true
	default:
		return false
	}
}

// FormatScrolled converts a scrolled state to JSON value.
func FormatScrolled(state int) any {
	// 0 = unset (nil), 1 = true, 2 = false, 3 = auto
	switch state {
	case 1:
		return true
	case 2:
		return false
	case 3:
		return "auto"
	default:
		return nil
	}
}
