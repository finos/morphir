package sources

import (
	"errors"
	"fmt"
	"io/fs"
	"os"

	"github.com/pelletier/go-toml/v2"
)

// TOMLSource is a configuration source that reads from a TOML file.
type TOMLSource struct {
	name     string
	path     string
	priority int
}

// NewTOMLSource creates a new TOML file source.
func NewTOMLSource(name, path string, priority int) *TOMLSource {
	return &TOMLSource{
		name:     name,
		path:     path,
		priority: priority,
	}
}

// Name returns the human-readable name for this source.
func (s *TOMLSource) Name() string {
	return s.name
}

// Priority returns the priority level for this source.
func (s *TOMLSource) Priority() int {
	return s.priority
}

// Path returns the file path for this source.
func (s *TOMLSource) Path() string {
	return s.path
}

// Exists checks whether the TOML file exists and is readable.
// Returns (false, nil) if the file does not exist.
// Returns (false, error) if there's a permission or other unexpected error.
// Returns (true, nil) if the file exists and is accessible.
func (s *TOMLSource) Exists() (bool, error) {
	info, err := os.Stat(s.path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return false, nil
		}
		return false, fmt.Errorf("sources.TOMLSource.Exists: %w", err)
	}

	if info.IsDir() {
		return false, nil
	}

	return true, nil
}

// Load reads and parses the TOML file.
// Returns (nil, nil) if the file does not exist.
// Returns (nil, error) if the file exists but cannot be read or parsed.
// Returns (map[string]any, nil) on success.
func (s *TOMLSource) Load() (map[string]any, error) {
	exists, err := s.Exists()
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}

	data, err := os.ReadFile(s.path)
	if err != nil {
		return nil, fmt.Errorf("sources.TOMLSource.Load: read file: %w", err)
	}

	var result map[string]any
	if err := toml.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("sources.TOMLSource.Load: parse TOML: %w", err)
	}

	return result, nil
}

// Ensure TOMLSource implements Source interface.
var _ Source = (*TOMLSource)(nil)
