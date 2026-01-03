package sources

import (
	"os"
	"strconv"
	"strings"
	"time"
)

// EnvSource is a configuration source that reads from environment variables.
// Environment variables are mapped to config keys using a prefix and underscore
// convention:
//
//	MORPHIR_IR_FORMAT_VERSION -> ir.format_version
//	MORPHIR_CODEGEN_TARGETS -> codegen.targets
//
// Nested keys use double underscores:
//
//	MORPHIR_CODEGEN__GO__PACKAGE -> codegen.go.package
type EnvSource struct {
	prefix   string
	priority int
	environ  func() []string // allows injection for testing
}

// NewEnvSource creates a new environment variable source.
// The prefix is prepended to all environment variable names (e.g., "MORPHIR").
func NewEnvSource(prefix string, priority int) *EnvSource {
	return &EnvSource{
		prefix:   strings.ToUpper(prefix),
		priority: priority,
		environ:  os.Environ,
	}
}

// newEnvSourceWithEnviron creates an EnvSource with a custom environ function for testing.
func newEnvSourceWithEnviron(prefix string, priority int, environ func() []string) *EnvSource {
	return &EnvSource{
		prefix:   strings.ToUpper(prefix),
		priority: priority,
		environ:  environ,
	}
}

// Name returns the human-readable name for this source.
func (s *EnvSource) Name() string {
	return "env"
}

// Priority returns the priority level for this source.
func (s *EnvSource) Priority() int {
	return s.priority
}

// Path returns a descriptive identifier for this source.
func (s *EnvSource) Path() string {
	return s.prefix + "_*"
}

// Exists always returns true for environment variable sources,
// as environment variables are always accessible.
func (s *EnvSource) Exists() (bool, error) {
	return true, nil
}

// Load reads all environment variables with the configured prefix
// and returns them as a nested map structure.
func (s *EnvSource) Load() (map[string]any, error) {
	result := make(map[string]any)
	prefixWithUnderscore := s.prefix + "_"

	for _, env := range s.environ() {
		parts := strings.SplitN(env, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key, value := parts[0], parts[1]
		if !strings.HasPrefix(key, prefixWithUnderscore) {
			continue
		}

		// Remove prefix and convert to config key path
		keyWithoutPrefix := strings.TrimPrefix(key, prefixWithUnderscore)
		keyPath := envKeyToPath(keyWithoutPrefix)

		// Convert value to appropriate type
		typedValue := parseEnvValue(value)

		// Set the value in the nested map
		setNestedValue(result, keyPath, typedValue)
	}

	if len(result) == 0 {
		return nil, nil
	}

	return result, nil
}

// envKeyToPath converts an environment variable key to a config key path.
// Single underscores separate section and key: IR_FORMAT_VERSION -> ["ir", "format_version"]
// Double underscores indicate nesting: CODEGEN__GO__PACKAGE -> ["codegen", "go", "package"]
func envKeyToPath(key string) []string {
	// First, split by double underscore for nesting
	segments := strings.Split(key, "__")

	var path []string
	for _, segment := range segments {
		// Convert to lowercase
		segment = strings.ToLower(segment)
		path = append(path, segment)
	}

	return path
}

// parseEnvValue attempts to parse an environment variable value into
// an appropriate Go type (bool, int64, duration, or string).
func parseEnvValue(value string) any {
	// Try boolean
	if b, err := strconv.ParseBool(value); err == nil {
		return b
	}

	// Try integer
	if i, err := strconv.ParseInt(value, 10, 64); err == nil {
		return i
	}

	// Try duration
	if d, err := time.ParseDuration(value); err == nil {
		return d
	}

	// Return as string
	return value
}

// setNestedValue sets a value in a nested map structure, creating
// intermediate maps as needed.
func setNestedValue(m map[string]any, path []string, value any) {
	if len(path) == 0 {
		return
	}

	if len(path) == 1 {
		m[path[0]] = value
		return
	}

	// Create or get intermediate map
	key := path[0]
	if _, ok := m[key]; !ok {
		m[key] = make(map[string]any)
	}

	if nested, ok := m[key].(map[string]any); ok {
		setNestedValue(nested, path[1:], value)
	}
}

// Ensure EnvSource implements Source interface.
var _ Source = (*EnvSource)(nil)
