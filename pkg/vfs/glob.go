package vfs

import (
	"errors"
	"strings"
)

// Glob represents a validated glob pattern.
type Glob struct {
	pattern string
}

// ParseGlob validates a glob pattern string.
func ParseGlob(raw string) (Glob, error) {
	if raw == "" {
		return Glob{}, errors.New("vfs: empty glob")
	}
	if strings.Contains(raw, "\\") {
		return Glob{}, errors.New("vfs: backslashes are not allowed in globs")
	}

	return Glob{pattern: raw}, nil
}

// MustGlob panics if the pattern is invalid.
func MustGlob(raw string) Glob {
	glob, err := ParseGlob(raw)
	if err != nil {
		panic(err)
	}
	return glob
}

// String returns the glob pattern.
func (g Glob) String() string {
	return g.pattern
}
