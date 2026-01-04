package sources

import (
	"errors"
	"fmt"
	"io/fs"
	"os"

	"github.com/joho/godotenv"
)

// DotEnvSource is a configuration source that reads from a .env file.
// The .env file format is parsed using godotenv, supporting standard
// dotenv syntax including comments, quotes, and variable expansion.
//
// Values are parsed using the same type conversion rules as EnvSource.
type DotEnvSource struct {
	name     string
	path     string
	prefix   string
	priority int
}

// NewDotEnvSource creates a new .env file source.
// The prefix filters which variables are loaded (e.g., "MORPHIR").
func NewDotEnvSource(name, path, prefix string, priority int) *DotEnvSource {
	return &DotEnvSource{
		name:     name,
		path:     path,
		prefix:   prefix,
		priority: priority,
	}
}

// Name returns the human-readable name for this source.
func (s *DotEnvSource) Name() string {
	return s.name
}

// Priority returns the priority level for this source.
func (s *DotEnvSource) Priority() int {
	return s.priority
}

// Path returns the file path for this source.
func (s *DotEnvSource) Path() string {
	return s.path
}

// Exists checks whether the .env file exists and is readable.
func (s *DotEnvSource) Exists() (bool, error) {
	info, err := os.Stat(s.path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return false, nil
		}
		return false, fmt.Errorf("sources.DotEnvSource.Exists: %w", err)
	}

	if info.IsDir() {
		return false, nil
	}

	return true, nil
}

// Load reads and parses the .env file, returning variables with the
// configured prefix as a nested map structure.
func (s *DotEnvSource) Load() (map[string]any, error) {
	exists, err := s.Exists()
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}

	envMap, err := godotenv.Read(s.path)
	if err != nil {
		return nil, fmt.Errorf("sources.DotEnvSource.Load: parse .env: %w", err)
	}

	// Convert to environ format for processing
	environ := make([]string, 0, len(envMap))
	for k, v := range envMap {
		environ = append(environ, k+"="+v)
	}

	// Use EnvSource logic to parse the environment variables
	envSource := newEnvSourceWithEnviron(s.prefix, s.priority, func() []string {
		return environ
	})

	return envSource.Load()
}

// Ensure DotEnvSource implements Source interface.
var _ Source = (*DotEnvSource)(nil)
