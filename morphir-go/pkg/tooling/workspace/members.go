package workspace

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
)

// DiscoverMembers finds all workspace members matching the given glob patterns.
// It returns absolute paths to directories containing valid project configurations.
//
// Pattern types:
//   - Directory patterns (e.g., "packages/*", "libs/**"): Match directories and look
//     for default config files (morphir.toml, .morphir/morphir.toml, morphir.json)
//   - File patterns (e.g., "packages/**/morphir.toml", "configs/*.json"): Match specific
//     config files directly; the parent directory becomes the member
//
// Parameters:
//   - root: absolute path to workspace root
//   - patterns: glob patterns for member discovery
//   - excludes: patterns to exclude from results (e.g., "**/testdata")
//
// Returns paths in sorted order for deterministic behavior.
func DiscoverMembers(root string, patterns []string, excludes []string) ([]string, error) {
	if len(patterns) == 0 {
		return []string{}, nil
	}

	if err := validateRootDirectory(root); err != nil {
		return nil, err
	}

	memberSet := collectMembers(root, patterns, excludes)
	return sortedKeys(memberSet), nil
}

// validateRootDirectory ensures the root path exists and is a directory.
func validateRootDirectory(root string) error {
	info, err := os.Stat(root)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return &DiscoverError{StartDir: root, Err: ErrNotDirectory}
	}
	return nil
}

// collectMembers gathers all matching member directories into a set.
func collectMembers(root string, patterns, excludes []string) map[string]struct{} {
	memberSet := make(map[string]struct{})

	for _, pattern := range patterns {
		matches := expandPattern(root, pattern)
		for _, match := range matches {
			memberDir := resolveMemberDir(match)
			if memberDir != "" && isValidMember(root, memberDir, match, excludes) {
				memberSet[memberDir] = struct{}{}
			}
		}
	}

	return memberSet
}

// expandPattern resolves a glob pattern to matching paths.
func expandPattern(root, pattern string) []string {
	absPattern := filepath.Join(root, pattern)
	matches, err := doublestar.FilepathGlob(absPattern)
	if err != nil {
		return nil
	}
	return matches
}

// resolveMemberDir determines the member directory from a glob match.
// If the match is a file, returns its parent directory.
// If the match is a directory, returns the directory itself.
func resolveMemberDir(match string) string {
	info, err := os.Stat(match)
	if err != nil {
		return ""
	}

	if info.IsDir() {
		return match
	}

	// Match is a file - return parent directory
	return filepath.Dir(match)
}

// isValidMember checks if a path is a valid workspace member.
// Parameters:
//   - root: workspace root for relative path calculation
//   - memberDir: the directory to validate as a member
//   - matchedPath: the original glob match (may be a file or directory)
//   - excludes: patterns to exclude
func isValidMember(root, memberDir, matchedPath string, excludes []string) bool {
	if isExcluded(root, memberDir, excludes) {
		return false
	}

	// If the match was a file, we trust it exists (glob matched it)
	// Just verify it's a config file we can use
	if matchedPath != memberDir {
		return isConfigFile(matchedPath)
	}

	// Match was a directory - look for default config files
	return HasProjectConfig(memberDir)
}

// isConfigFile checks if a file path looks like a config file we can load.
// Currently supports .toml and .json extensions.
func isConfigFile(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	return ext == ".toml" || ext == ".json"
}

// sortedKeys returns the keys of a map as a sorted slice.
func sortedKeys(m map[string]struct{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// isExcluded checks if a path matches any exclude pattern.
func isExcluded(root, path string, excludes []string) bool {
	if len(excludes) == 0 {
		return false
	}

	// Get relative path for pattern matching
	relPath, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}

	for _, pattern := range excludes {
		// Try matching against the relative path
		matched, err := doublestar.Match(pattern, relPath)
		if err == nil && matched {
			return true
		}

		// Also try matching against just the base name for simple patterns
		matched, err = doublestar.Match(pattern, filepath.Base(path))
		if err == nil && matched {
			return true
		}
	}

	return false
}

// HasProjectConfig checks if a directory contains a valid project configuration.
// A valid project config is one of:
//   - morphir.toml with [project] section
//   - .morphir/morphir.toml with [project] section
//   - morphir.json (legacy format)
func HasProjectConfig(dir string) bool {
	_, _, found := FindProjectConfig(dir)
	return found
}

// FindProjectConfig locates the project configuration file in a directory.
// It returns the path, format, and whether it was found.
//
// Detection priority:
//  1. morphir.toml with [project] section
//  2. .morphir/morphir.toml with [project] section
//  3. morphir.json (legacy format)
func FindProjectConfig(dir string) (path string, format string, found bool) {
	// Check morphir.toml first
	tomlPath := filepath.Join(dir, "morphir.toml")
	if hasProjectSection(tomlPath) {
		return tomlPath, "toml", true
	}

	// Check .morphir/morphir.toml
	hiddenTomlPath := filepath.Join(dir, ".morphir", "morphir.toml")
	if hasProjectSection(hiddenTomlPath) {
		return hiddenTomlPath, "toml", true
	}

	// Check morphir.json (legacy)
	jsonPath := filepath.Join(dir, "morphir.json")
	if isRegularFile(jsonPath) {
		return jsonPath, "json", true
	}

	return "", "", false
}

// FindProjectConfigByPath returns the config format for a specific config file path.
// This is used when a glob pattern matched a specific file rather than a directory.
func FindProjectConfigByPath(configPath string) (format string, found bool) {
	if !isRegularFile(configPath) {
		return "", false
	}

	ext := strings.ToLower(filepath.Ext(configPath))
	switch ext {
	case ".toml":
		if hasProjectSection(configPath) {
			return "toml", true
		}
		return "", false
	case ".json":
		return "json", true
	default:
		return "", false
	}
}

// hasProjectSection checks if a TOML file exists and contains a [project] section.
func hasProjectSection(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}

	// Simple check for [project] section
	// This is a basic check - full parsing would be done when loading
	content := string(data)
	return strings.Contains(content, "[project]")
}

// isRegularFile checks if a path exists and is a regular file.
func isRegularFile(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}
