package json

import (
	"encoding/json"
	"fmt"
	"io"
)

// DecodeNotebook decodes a notebook from JSON data.
func DecodeNotebook(data []byte) (*NotebookJSON, error) {
	var nb NotebookJSON
	if err := json.Unmarshal(data, &nb); err != nil {
		return nil, fmt.Errorf("failed to decode notebook: %w", err)
	}
	return &nb, nil
}

// DecodeNotebookFromReader decodes a notebook from a reader.
func DecodeNotebookFromReader(r io.Reader) (*NotebookJSON, error) {
	var nb NotebookJSON
	decoder := json.NewDecoder(r)
	if err := decoder.Decode(&nb); err != nil {
		return nil, fmt.Errorf("failed to decode notebook: %w", err)
	}
	return &nb, nil
}

// DecodeCell decodes a single cell from JSON data.
func DecodeCell(data []byte) (*CellJSON, error) {
	var cell CellJSON
	if err := json.Unmarshal(data, &cell); err != nil {
		return nil, fmt.Errorf("failed to decode cell: %w", err)
	}
	return &cell, nil
}

// DecodeOutput decodes a single output from JSON data.
func DecodeOutput(data []byte) (*OutputJSON, error) {
	var output OutputJSON
	if err := json.Unmarshal(data, &output); err != nil {
		return nil, fmt.Errorf("failed to decode output: %w", err)
	}
	return &output, nil
}

// ParseScrolled parses the scrolled field which can be bool, "auto", or absent.
func ParseScrolled(v any) (scrolled int) {
	// 0 = unset, 1 = true, 2 = false, 3 = auto
	if v == nil {
		return 0
	}
	switch val := v.(type) {
	case bool:
		if val {
			return 1
		}
		return 2
	case string:
		if val == "auto" {
			return 3
		}
	}
	return 0
}

// ParseMimeBundle converts a map to typed values, handling multiline strings.
func ParseMimeBundle(data map[string]any) map[string]any {
	if data == nil {
		return nil
	}
	result := make(map[string]any, len(data))
	for k, v := range data {
		result[k] = normalizeMimeValue(v)
	}
	return result
}

// normalizeMimeValue converts array-of-strings to single string for text types.
func normalizeMimeValue(v any) any {
	switch val := v.(type) {
	case []any:
		// Check if all elements are strings
		var parts []string
		allStrings := true
		for _, item := range val {
			if s, ok := item.(string); ok {
				parts = append(parts, s)
			} else {
				allStrings = false
				break
			}
		}
		if allStrings && len(parts) > 0 {
			return joinLines(parts)
		}
		return val
	default:
		return val
	}
}

// joinLines joins lines, handling the case where lines already have newlines.
func joinLines(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	var result string
	for _, line := range lines {
		result += line
	}
	return result
}
