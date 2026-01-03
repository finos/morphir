package report

import (
	"encoding/json"
	"strconv"
	"strings"
)

// ContextExtractor extracts and formats JSON context around error locations.
type ContextExtractor struct {
	// MaxDepth limits how deep to render nested structures.
	MaxDepth int
	// MaxArrayItems limits how many array items to show.
	MaxArrayItems int
	// MaxStringLength limits string value lengths.
	MaxStringLength int
}

// DefaultContextExtractor returns a context extractor with sensible defaults.
func DefaultContextExtractor() *ContextExtractor {
	return &ContextExtractor{
		MaxDepth:        3,
		MaxArrayItems:   5,
		MaxStringLength: 100,
	}
}

// ExtractContext extracts the JSON value at the given path and formats it.
func (e *ContextExtractor) ExtractContext(data any, jsonPath string) string {
	if data == nil {
		return ""
	}

	// Navigate to the target location
	value := e.NavigateToPath(data, jsonPath)
	if value == nil {
		return ""
	}

	// Format the value
	return e.formatValue(value, 0)
}

// ExtractContextWithParent extracts context showing the parent structure.
func (e *ContextExtractor) ExtractContextWithParent(data any, jsonPath string) string {
	if data == nil {
		return ""
	}

	// Get parent path
	parentPath := getParentPath(jsonPath)
	if parentPath == "" {
		parentPath = jsonPath
	}

	// Navigate to parent
	parent := e.NavigateToPath(data, parentPath)
	if parent == nil {
		// Fall back to direct path
		parent = e.NavigateToPath(data, jsonPath)
	}
	if parent == nil {
		return ""
	}

	return e.formatValue(parent, 0)
}

// NavigateToPath traverses the data structure following the JSON path.
func (e *ContextExtractor) NavigateToPath(data any, path string) any {
	if path == "" || path == "/" {
		return data
	}

	// Split path into components
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")

	current := data
	for _, part := range parts {
		if part == "" {
			continue
		}

		switch v := current.(type) {
		case map[string]any:
			var ok bool
			current, ok = v[part]
			if !ok {
				return nil
			}
		case []any:
			idx, err := strconv.Atoi(part)
			if err != nil || idx < 0 || idx >= len(v) {
				return nil
			}
			current = v[idx]
		default:
			return nil
		}
	}

	return current
}

// formatValue formats a value for display in a code block.
func (e *ContextExtractor) formatValue(value any, depth int) string {
	if depth > e.MaxDepth {
		return e.summarizeValue(value)
	}

	switch v := value.(type) {
	case map[string]any:
		return e.formatObject(v, depth)
	case []any:
		return e.formatArray(v, depth)
	case string:
		if len(v) > e.MaxStringLength {
			return `"` + v[:e.MaxStringLength] + `..."`
		}
		return `"` + v + `"`
	case float64:
		if v == float64(int(v)) {
			return strconv.Itoa(int(v))
		}
		return strconv.FormatFloat(v, 'f', -1, 64)
	case bool:
		if v {
			return "true"
		}
		return "false"
	case nil:
		return "null"
	default:
		// Try JSON marshaling as fallback
		b, err := json.Marshal(v)
		if err != nil {
			return "..."
		}
		return string(b)
	}
}

// formatObject formats a map as a JSON object.
func (e *ContextExtractor) formatObject(obj map[string]any, depth int) string {
	if len(obj) == 0 {
		return "{}"
	}

	var sb strings.Builder
	sb.WriteString("{\n")

	indent := strings.Repeat("  ", depth+1)
	count := 0
	for key, val := range obj {
		if count > 0 {
			sb.WriteString(",\n")
		}
		sb.WriteString(indent)
		sb.WriteString(`"`)
		sb.WriteString(key)
		sb.WriteString(`": `)
		sb.WriteString(e.formatValue(val, depth+1))
		count++

		// Limit number of keys shown
		if count >= e.MaxArrayItems {
			if len(obj) > count {
				sb.WriteString(",\n")
				sb.WriteString(indent)
				sb.WriteString("// ... ")
				sb.WriteString(strconv.Itoa(len(obj) - count))
				sb.WriteString(" more properties")
			}
			break
		}
	}

	sb.WriteString("\n")
	sb.WriteString(strings.Repeat("  ", depth))
	sb.WriteString("}")

	return sb.String()
}

// formatArray formats a slice as a JSON array.
func (e *ContextExtractor) formatArray(arr []any, depth int) string {
	if len(arr) == 0 {
		return "[]"
	}

	// For small arrays with simple values, use inline format
	if len(arr) <= 3 && e.isSimpleArray(arr) {
		return e.formatArrayInline(arr, depth)
	}

	var sb strings.Builder
	sb.WriteString("[\n")

	indent := strings.Repeat("  ", depth+1)
	for i, val := range arr {
		if i > 0 {
			sb.WriteString(",\n")
		}
		sb.WriteString(indent)
		sb.WriteString(e.formatValue(val, depth+1))

		// Limit number of items shown
		if i >= e.MaxArrayItems-1 {
			if len(arr) > i+1 {
				sb.WriteString(",\n")
				sb.WriteString(indent)
				sb.WriteString("// ... ")
				sb.WriteString(strconv.Itoa(len(arr) - i - 1))
				sb.WriteString(" more items")
			}
			break
		}
	}

	sb.WriteString("\n")
	sb.WriteString(strings.Repeat("  ", depth))
	sb.WriteString("]")

	return sb.String()
}

// formatArrayInline formats a simple array on one line.
func (e *ContextExtractor) formatArrayInline(arr []any, depth int) string {
	var parts []string
	for _, val := range arr {
		parts = append(parts, e.formatValue(val, depth+1))
	}
	return "[" + strings.Join(parts, ", ") + "]"
}

// isSimpleArray checks if an array contains only simple values.
func (e *ContextExtractor) isSimpleArray(arr []any) bool {
	for _, v := range arr {
		switch v.(type) {
		case map[string]any, []any:
			return false
		}
	}
	return true
}

// summarizeValue creates a short summary of a complex value.
func (e *ContextExtractor) summarizeValue(value any) string {
	switch v := value.(type) {
	case map[string]any:
		return "{...}" // + strconv.Itoa(len(v)) + " properties}"
	case []any:
		return "[..." + strconv.Itoa(len(v)) + " items]"
	case string:
		if len(v) > 20 {
			return `"` + v[:20] + `..."`
		}
		return `"` + v + `"`
	default:
		return e.formatValue(v, 0)
	}
}

// getParentPath returns the parent path of a JSON path.
func getParentPath(path string) string {
	if path == "" || path == "/" {
		return ""
	}

	path = strings.TrimPrefix(path, "/")
	lastSlash := strings.LastIndex(path, "/")
	if lastSlash == -1 {
		return "/"
	}

	return "/" + path[:lastSlash]
}

// FormatMorphirName converts a Name array ([]any of strings) to a friendly camelCase representation.
// Example: ["value", "in", "u", "s", "d"] -> "valueInUSD"
func FormatMorphirName(value any) string {
	arr, ok := value.([]any)
	if !ok || len(arr) == 0 {
		return ""
	}

	var parts []string
	for _, item := range arr {
		if s, ok := item.(string); ok {
			parts = append(parts, s)
		}
	}

	if len(parts) == 0 {
		return ""
	}

	// Format as camelCase
	result := parts[0]
	for i := 1; i < len(parts); i++ {
		word := parts[i]
		if len(word) > 0 {
			result += strings.ToUpper(word[:1]) + word[1:]
		}
	}

	return result
}

// FormatMorphirPath converts a Path (array of Names) to a dot-separated representation.
// Example: [["morphir"], ["s", "d", "k"]] -> "Morphir.SDK"
func FormatMorphirPath(value any) string {
	arr, ok := value.([]any)
	if !ok || len(arr) == 0 {
		return ""
	}

	var names []string
	for _, item := range arr {
		name := FormatMorphirName(item)
		if name != "" {
			// Capitalize first letter for module/package names
			names = append(names, strings.ToUpper(name[:1])+name[1:])
		}
	}

	return strings.Join(names, ".")
}

// IsNameArray checks if a value looks like a Morphir Name (array of lowercase strings).
func IsNameArray(value any) bool {
	arr, ok := value.([]any)
	if !ok || len(arr) == 0 {
		return false
	}

	for _, item := range arr {
		if _, ok := item.(string); !ok {
			return false
		}
	}
	return true
}

// IsPathArray checks if a value looks like a Morphir Path (array of Names).
func IsPathArray(value any) bool {
	arr, ok := value.([]any)
	if !ok || len(arr) == 0 {
		return false
	}

	for _, item := range arr {
		if !IsNameArray(item) {
			return false
		}
	}
	return true
}
