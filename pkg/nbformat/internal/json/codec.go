package json

import (
	"encoding/json"
	"strings"
)

// NotebookJSON represents the JSON structure of a Jupyter notebook.
type NotebookJSON struct {
	NBFormat      int                  `json:"nbformat"`
	NBFormatMinor int                  `json:"nbformat_minor"`
	Metadata      NotebookMetadataJSON `json:"metadata"`
	Cells         []CellJSON           `json:"cells"`
}

// NotebookMetadataJSON represents the JSON structure of notebook metadata.
type NotebookMetadataJSON struct {
	KernelSpec   *KernelSpecJSON   `json:"kernelspec,omitempty"`
	LanguageInfo *LanguageInfoJSON `json:"language_info,omitempty"`
	Title        string            `json:"title,omitempty"`
	Authors      []AuthorJSON      `json:"authors,omitempty"`
	// Additional fields are captured here
	Extra map[string]any `json:"-"`
}

// KernelSpecJSON represents the JSON structure of kernel specification.
type KernelSpecJSON struct {
	Name        string `json:"name"`
	DisplayName string `json:"display_name"`
	Language    string `json:"language,omitempty"`
}

// LanguageInfoJSON represents the JSON structure of language information.
type LanguageInfoJSON struct {
	Name              string `json:"name"`
	Version           string `json:"version,omitempty"`
	MimeType          string `json:"mimetype,omitempty"`
	FileExtension     string `json:"file_extension,omitempty"`
	PygmentsLexer     string `json:"pygments_lexer,omitempty"`
	CodemirrorMode    any    `json:"codemirror_mode,omitempty"`
	NBConvertExporter string `json:"nbconvert_exporter,omitempty"`
}

// AuthorJSON represents the JSON structure of an author.
type AuthorJSON struct {
	Name string `json:"name"`
}

// CellJSON represents the JSON structure of a notebook cell.
type CellJSON struct {
	ID             string           `json:"id,omitempty"`
	CellType       string           `json:"cell_type"`
	Source         MultilineString  `json:"source"`
	Metadata       CellMetadataJSON `json:"metadata"`
	ExecutionCount *int             `json:"execution_count,omitempty"`
	Outputs        []OutputJSON     `json:"outputs,omitempty"`
	Attachments    map[string]any   `json:"attachments,omitempty"`
}

// CellMetadataJSON represents the JSON structure of cell metadata.
type CellMetadataJSON struct {
	Collapsed bool                 `json:"collapsed,omitempty"`
	Scrolled  any                  `json:"scrolled,omitempty"` // bool, "auto", or absent
	Deletable *bool                `json:"deletable,omitempty"`
	Editable  *bool                `json:"editable,omitempty"`
	Name      string               `json:"name,omitempty"`
	Tags      []string             `json:"tags,omitempty"`
	Jupyter   *JupyterCellMetaJSON `json:"jupyter,omitempty"`
	Extra     map[string]any       `json:"-"`
}

// JupyterCellMetaJSON represents the Jupyter-specific cell metadata.
type JupyterCellMetaJSON struct {
	SourceHidden  bool `json:"source_hidden,omitempty"`
	OutputsHidden bool `json:"outputs_hidden,omitempty"`
}

// OutputJSON represents the JSON structure of a cell output.
type OutputJSON struct {
	OutputType     string          `json:"output_type"`
	Name           string          `json:"name,omitempty"`            // stream
	Text           MultilineString `json:"text,omitempty"`            // stream
	Data           map[string]any  `json:"data,omitempty"`            // display_data, execute_result
	Metadata       map[string]any  `json:"metadata,omitempty"`        // display_data, execute_result
	ExecutionCount *int            `json:"execution_count,omitempty"` // execute_result
	Ename          string          `json:"ename,omitempty"`           // error
	Evalue         string          `json:"evalue,omitempty"`          // error
	Traceback      []string        `json:"traceback,omitempty"`       // error
}

// MultilineString handles JSON fields that can be either a string or array of strings.
// In nbformat, source and text fields can be stored either way.
type MultilineString string

// UnmarshalJSON implements json.Unmarshaler.
func (m *MultilineString) UnmarshalJSON(data []byte) error {
	// Try as string first
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*m = MultilineString(s)
		return nil
	}

	// Try as array of strings
	var arr []string
	if err := json.Unmarshal(data, &arr); err != nil {
		return err
	}
	*m = MultilineString(strings.Join(arr, ""))
	return nil
}

// MarshalJSON implements json.Marshaler.
// We always marshal as an array of lines to match Jupyter's standard output.
func (m MultilineString) MarshalJSON() ([]byte, error) {
	s := string(m)
	if s == "" {
		return json.Marshal([]string{})
	}

	// Split into lines, preserving line endings
	lines := splitLines(s)
	return json.Marshal(lines)
}

// String returns the string value.
func (m MultilineString) String() string {
	return string(m)
}

// splitLines splits a string into lines, preserving line endings on each line
// except the last (if it doesn't end with a newline).
func splitLines(s string) []string {
	if s == "" {
		return []string{}
	}

	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i+1])
			start = i + 1
		}
	}
	// Add remaining content if any
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// MimeBundleJSON represents MIME data that can contain various types.
// Values can be strings, arrays of strings, or other JSON types.
type MimeBundleJSON map[string]any

// GetString returns the value as a string, joining arrays if necessary.
func (m MimeBundleJSON) GetString(mimeType string) (string, bool) {
	v, ok := m[mimeType]
	if !ok {
		return "", false
	}

	switch val := v.(type) {
	case string:
		return val, true
	case []any:
		var parts []string
		for _, item := range val {
			if s, ok := item.(string); ok {
				parts = append(parts, s)
			}
		}
		return strings.Join(parts, ""), true
	case []string:
		return strings.Join(val, ""), true
	default:
		return "", false
	}
}
