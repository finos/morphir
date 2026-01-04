// Package sources provides internal configuration source implementations.
//
// This package is internal and should not be imported by external code.
// Use the public config package API instead.
package sources

// Source represents a configuration source that can be loaded.
// Sources have a name, priority, and path, and can check for existence
// and load their contents as a generic map.
type Source interface {
	// Name returns a human-readable name for this source.
	// Examples: "system", "global", "project", "user", "env"
	Name() string

	// Priority returns the priority level for this source.
	// Higher values take precedence over lower values when merging.
	Priority() int

	// Path returns the file path or identifier for this source.
	// For file-based sources, this is the file path.
	// For other sources (like env vars), this may be a descriptive identifier.
	Path() string

	// Exists checks whether this source exists and is accessible.
	// Returns true if the source can be loaded, false otherwise.
	// An error is returned only for unexpected failures (e.g., permission errors),
	// not for the source simply not existing.
	Exists() (bool, error)

	// Load reads the configuration from this source.
	// Returns a map of configuration values that can be merged with other sources.
	// Returns an error if the source exists but cannot be read or parsed.
	// If the source does not exist, implementations should return (nil, nil).
	Load() (map[string]any, error)
}
