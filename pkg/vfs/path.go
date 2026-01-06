package vfs

import (
	"errors"
	"strings"
)

// VPath is a normalized, POSIX-like path.
type VPath struct {
	value string
}

// ParseVPath validates and normalizes a raw path string.
func ParseVPath(raw string) (VPath, error) {
	if raw == "" {
		return VPath{}, errors.New("vfs: empty path")
	}
	if strings.Contains(raw, "\\") {
		return VPath{}, errors.New("vfs: backslashes are not allowed in VPath")
	}

	abs := strings.HasPrefix(raw, "/")
	segments := strings.Split(raw, "/")
	stack := make([]string, 0, len(segments))

	for _, seg := range segments {
		switch seg {
		case "", ".":
			continue
		case "..":
			if len(stack) == 0 {
				return VPath{}, errors.New("vfs: path escapes root")
			}
			stack = stack[:len(stack)-1]
		default:
			stack = append(stack, seg)
		}
	}

	normalized := strings.Join(stack, "/")
	if abs {
		if normalized == "" {
			normalized = "/"
		} else {
			normalized = "/" + normalized
		}
	}

	if !abs && normalized == "" {
		return VPath{}, errors.New("vfs: empty relative path")
	}

	return VPath{value: normalized}, nil
}

// MustVPath panics if the path is invalid.
func MustVPath(raw string) VPath {
	path, err := ParseVPath(raw)
	if err != nil {
		panic(err)
	}
	return path
}

// String returns the normalized path value.
func (p VPath) String() string {
	return p.value
}

// Join appends path segments and re-normalizes.
func (p VPath) Join(parts ...string) (VPath, error) {
	if len(parts) == 0 {
		return p, nil
	}

	raw := p.value
	for _, part := range parts {
		if part == "" {
			continue
		}
		if strings.HasSuffix(raw, "/") {
			raw += part
		} else {
			raw += "/" + part
		}
	}

	return ParseVPath(raw)
}
