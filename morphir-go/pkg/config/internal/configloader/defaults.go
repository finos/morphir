package configloader

// DefaultValues returns the built-in default configuration values.
// These represent the lowest priority configuration layer.
func DefaultValues() map[string]any {
	return map[string]any{
		"morphir": map[string]any{
			"version": "",
		},
		"workspace": map[string]any{
			"root":       "",
			"output_dir": ".morphir",
		},
		"ir": map[string]any{
			"format_version": int64(3),
			"strict_mode":    false,
		},
		"codegen": map[string]any{
			"targets":       []string{},
			"template_dir":  "",
			"output_format": "pretty",
		},
		"cache": map[string]any{
			"enabled":  true,
			"dir":      "",
			"max_size": int64(0),
		},
		"logging": map[string]any{
			"level":  "info",
			"format": "text",
			"file":   "",
		},
		"ui": map[string]any{
			"color":       true,
			"interactive": true,
			"theme":       "default",
		},
	}
}

// GetString retrieves a string value from a nested map using a dot-separated path.
// Returns the default value if the path doesn't exist or isn't a string.
func GetString(m map[string]any, path string, defaultVal string) string {
	val := getNestedValue(m, path)
	if s, ok := val.(string); ok {
		return s
	}
	return defaultVal
}

// GetInt retrieves an integer value from a nested map using a dot-separated path.
// Returns the default value if the path doesn't exist or isn't an integer.
func GetInt(m map[string]any, path string, defaultVal int) int {
	val := getNestedValue(m, path)
	switch v := val.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	}
	return defaultVal
}

// GetInt64 retrieves an int64 value from a nested map using a dot-separated path.
// Returns the default value if the path doesn't exist or isn't an integer.
func GetInt64(m map[string]any, path string, defaultVal int64) int64 {
	val := getNestedValue(m, path)
	switch v := val.(type) {
	case int64:
		return v
	case int:
		return int64(v)
	case float64:
		return int64(v)
	}
	return defaultVal
}

// GetBool retrieves a boolean value from a nested map using a dot-separated path.
// Returns the default value if the path doesn't exist or isn't a boolean.
func GetBool(m map[string]any, path string, defaultVal bool) bool {
	val := getNestedValue(m, path)
	if b, ok := val.(bool); ok {
		return b
	}
	return defaultVal
}

// GetStringSlice retrieves a string slice from a nested map using a dot-separated path.
// Returns the default value if the path doesn't exist or isn't a string slice.
func GetStringSlice(m map[string]any, path string, defaultVal []string) []string {
	val := getNestedValue(m, path)
	switch v := val.(type) {
	case []string:
		result := make([]string, len(v))
		copy(result, v)
		return result
	case []any:
		result := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				result = append(result, s)
			}
		}
		return result
	}
	return defaultVal
}

// getNestedValue retrieves a value from a nested map using a dot-separated path.
// Returns nil if any part of the path doesn't exist.
func getNestedValue(m map[string]any, path string) any {
	if m == nil || path == "" {
		return nil
	}

	// Split path by dots
	parts := splitPath(path)
	current := any(m)

	for _, part := range parts {
		currentMap, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current, ok = currentMap[part]
		if !ok {
			return nil
		}
	}

	return current
}

// splitPath splits a dot-separated path into parts.
func splitPath(path string) []string {
	if path == "" {
		return nil
	}

	var parts []string
	start := 0
	for i := 0; i < len(path); i++ {
		if path[i] == '.' {
			if i > start {
				parts = append(parts, path[start:i])
			}
			start = i + 1
		}
	}
	if start < len(path) {
		parts = append(parts, path[start:])
	}
	return parts
}
