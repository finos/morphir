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

// IsAbs returns true if the path is absolute (starts with /).
func (p VPath) IsAbs() bool {
	return strings.HasPrefix(p.value, "/")
}

// Base returns the last element of the path.
// For "/a/b/c", it returns "c".
// For "/a", it returns "a".
// For "/", it returns "/".
// For "a/b", it returns "b".
func (p VPath) Base() string {
	if p.value == "/" {
		return "/"
	}
	idx := strings.LastIndex(p.value, "/")
	if idx == -1 {
		return p.value
	}
	return p.value[idx+1:]
}

// Dir returns the directory portion of the path.
// For "/a/b/c", it returns "/a/b".
// For "/a", it returns "/".
// For "/", it returns "/".
// For "a/b", it returns "a".
// For "a", it returns ".".
func (p VPath) Dir() VPath {
	if p.value == "/" {
		return p
	}
	idx := strings.LastIndex(p.value, "/")
	if idx == -1 {
		// Relative path with single component
		return VPath{value: "."}
	}
	if idx == 0 {
		// Absolute path with single component like "/a"
		return VPath{value: "/"}
	}
	return VPath{value: p.value[:idx]}
}

// Ext returns the file extension including the dot.
// For "/a/b/file.txt", it returns ".txt".
// For "/a/b/file.tar.gz", it returns ".gz".
// For "/a/b/file", it returns "".
// For "/a/b/.dotfile", it returns "".
func (p VPath) Ext() string {
	base := p.Base()
	if base == "/" || base == "." {
		return ""
	}
	// Don't treat leading dot as extension (e.g., .dotfile)
	if strings.HasPrefix(base, ".") {
		base = base[1:]
	}
	idx := strings.LastIndex(base, ".")
	if idx == -1 {
		return ""
	}
	return "." + base[idx+1:]
}

// Stem returns the base name without the extension.
// For "/a/b/file.txt", it returns "file".
// For "/a/b/file.tar.gz", it returns "file.tar".
// For "/a/b/file", it returns "file".
// For "/a/b/.dotfile", it returns ".dotfile".
func (p VPath) Stem() string {
	base := p.Base()
	if base == "/" || base == "." {
		return base
	}
	ext := p.Ext()
	if ext == "" {
		return base
	}
	return base[:len(base)-len(ext)]
}

// Rel computes a relative path from this path to the target.
// Both paths must be either both absolute or both relative.
// Returns an error if the paths have different roots or if computation is not possible.
func (p VPath) Rel(target VPath) (VPath, error) {
	if p.IsAbs() != target.IsAbs() {
		return VPath{}, errors.New("vfs: cannot compute relative path between absolute and relative paths")
	}

	if p.value == target.value {
		return VPath{value: "."}, nil
	}

	pSegments := splitPathString(p.value)
	tSegments := splitPathString(target.value)

	// Find common prefix
	commonLen := 0
	for i := 0; i < len(pSegments) && i < len(tSegments); i++ {
		if pSegments[i] != tSegments[i] {
			break
		}
		commonLen++
	}

	// Build relative path
	var parts []string

	// Add ".." for each remaining segment in source path
	for i := commonLen; i < len(pSegments); i++ {
		parts = append(parts, "..")
	}

	// Add remaining segments from target path
	parts = append(parts, tSegments[commonLen:]...)

	if len(parts) == 0 {
		return VPath{value: "."}, nil
	}

	return VPath{value: strings.Join(parts, "/")}, nil
}

// CommonRoot finds the common parent path of a set of paths.
// All paths must be either all absolute or all relative.
// Returns an error if paths are mixed absolute/relative or if the slice is empty.
// If there is no common root, returns the root path for absolute paths ("/")
// or an error for relative paths.
func CommonRoot(paths []VPath) (VPath, error) {
	if len(paths) == 0 {
		return VPath{}, errors.New("vfs: cannot find common root of empty path list")
	}

	if len(paths) == 1 {
		return paths[0], nil
	}

	// Check that all paths have the same absolute/relative nature
	isAbs := paths[0].IsAbs()
	for i := 1; i < len(paths); i++ {
		if paths[i].IsAbs() != isAbs {
			return VPath{}, errors.New("vfs: cannot find common root of mixed absolute and relative paths")
		}
	}

	// Split all paths into segments
	allSegments := make([][]string, len(paths))
	minLen := -1
	for i, p := range paths {
		allSegments[i] = splitPathString(p.value)
		if minLen == -1 || len(allSegments[i]) < minLen {
			minLen = len(allSegments[i])
		}
	}

	// Find common prefix length
	commonLen := 0
	for i := 0; i < minLen; i++ {
		segment := allSegments[0][i]
		allMatch := true
		for j := 1; j < len(allSegments); j++ {
			if allSegments[j][i] != segment {
				allMatch = false
				break
			}
		}
		if !allMatch {
			break
		}
		commonLen++
	}

	// Build common root path
	if commonLen == 0 {
		if isAbs {
			return VPath{value: "/"}, nil
		}
		return VPath{}, errors.New("vfs: no common root found for relative paths")
	}

	commonSegments := allSegments[0][:commonLen]
	commonPath := strings.Join(commonSegments, "/")
	if isAbs {
		commonPath = "/" + commonPath
	}

	return VPath{value: commonPath}, nil
}

// splitPathString splits a path string into segments, handling absolute paths correctly.
func splitPathString(path string) []string {
	if path == "/" {
		return []string{}
	}
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		return []string{}
	}
	return strings.Split(path, "/")
}
