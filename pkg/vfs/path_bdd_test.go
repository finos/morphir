package vfs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// BDD-style tests for VPath helpers using scenario outlines

func TestVPathBDD_PathParsing(t *testing.T) {
	scenarios := []struct {
		scenario string
		given    string
		when     string
		then     string
	}{
		{
			scenario: "Parsing absolute path with redundant separators",
			given:    "/a//b///c",
			when:     "parsed as VPath",
			then:     "/a/b/c",
		},
		{
			scenario: "Parsing path with current directory markers",
			given:    "/a/./b/./c",
			when:     "parsed as VPath",
			then:     "/a/b/c",
		},
		{
			scenario: "Parsing path with parent directory markers",
			given:    "/a/b/../c",
			when:     "parsed as VPath",
			then:     "/a/c",
		},
		{
			scenario: "Parsing relative path",
			given:    "a/b/c",
			when:     "parsed as VPath",
			then:     "a/b/c",
		},
		{
			scenario: "Parsing root path",
			given:    "/",
			when:     "parsed as VPath",
			then:     "/",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// Given: a raw path string
			raw := s.given

			// When: parsed as VPath
			path, err := ParseVPath(raw)
			require.NoError(t, err)

			// Then: should be normalized correctly
			require.Equal(t, s.then, path.String())
		})
	}
}

func TestVPathBDD_PathManipulation(t *testing.T) {
	scenarios := []struct {
		scenario  string
		givenPath string
		operation string
		args      []string
		expected  string
	}{
		{
			scenario:  "Joining paths",
			givenPath: "/a/b",
			operation: "join",
			args:      []string{"c", "d"},
			expected:  "/a/b/c/d",
		},
		{
			scenario:  "Joining with parent directory",
			givenPath: "/a/b/c",
			operation: "join",
			args:      []string{"..", "d"},
			expected:  "/a/b/d",
		},
		{
			scenario:  "Joining relative paths",
			givenPath: "a/b",
			operation: "join",
			args:      []string{"c"},
			expected:  "a/b/c",
		},
		{
			scenario:  "Getting base of file path",
			givenPath: "/workspace/src/main.go",
			operation: "base",
			expected:  "main.go",
		},
		{
			scenario:  "Getting directory of file path",
			givenPath: "/workspace/src/main.go",
			operation: "dir",
			expected:  "/workspace/src",
		},
		{
			scenario:  "Getting extension",
			givenPath: "/workspace/src/main.go",
			operation: "ext",
			expected:  ".go",
		},
		{
			scenario:  "Getting stem",
			givenPath: "/workspace/src/main.go",
			operation: "stem",
			expected:  "main",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// Given: a VPath
			path := MustVPath(s.givenPath)

			// When: performing operation
			var result string
			switch s.operation {
			case "join":
				joined, err := path.Join(s.args...)
				require.NoError(t, err)
				result = joined.String()
			case "base":
				result = path.Base()
			case "dir":
				result = path.Dir().String()
			case "ext":
				result = path.Ext()
			case "stem":
				result = path.Stem()
			}

			// Then: should produce expected result
			require.Equal(t, s.expected, result)
		})
	}
}

func TestVPathBDD_FileExtensions(t *testing.T) {
	scenarios := []struct {
		scenario string
		path     string
		ext      string
		stem     string
	}{
		{
			scenario: "Simple file extension",
			path:     "file.txt",
			ext:      ".txt",
			stem:     "file",
		},
		{
			scenario: "Multiple extensions",
			path:     "archive.tar.gz",
			ext:      ".gz",
			stem:     "archive.tar",
		},
		{
			scenario: "No extension",
			path:     "README",
			ext:      "",
			stem:     "README",
		},
		{
			scenario: "Dotfile without extension",
			path:     ".gitignore",
			ext:      "",
			stem:     ".gitignore",
		},
		{
			scenario: "Dotfile with extension",
			path:     ".config.json",
			ext:      ".json",
			stem:     ".config",
		},
		{
			scenario: "Path with directory and file",
			path:     "/workspace/src/main.go",
			ext:      ".go",
			stem:     "main",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// Given: a file path
			path := MustVPath(s.path)

			// When: extracting extension and stem
			ext := path.Ext()
			stem := path.Stem()

			// Then: should match expected values
			require.Equal(t, s.ext, ext, "extension should match")
			require.Equal(t, s.stem, stem, "stem should match")
		})
	}
}

func TestVPathBDD_RelativePaths(t *testing.T) {
	scenarios := []struct {
		scenario string
		from     string
		to       string
		expected string
	}{
		{
			scenario: "Same path",
			from:     "/workspace/src",
			to:       "/workspace/src",
			expected: ".",
		},
		{
			scenario: "Navigating to sibling",
			from:     "/workspace/src",
			to:       "/workspace/test",
			expected: "../test",
		},
		{
			scenario: "Navigating to child",
			from:     "/workspace",
			to:       "/workspace/src/utils",
			expected: "src/utils",
		},
		{
			scenario: "Navigating to parent",
			from:     "/workspace/src/utils",
			to:       "/workspace/src",
			expected: "..",
		},
		{
			scenario: "Navigating to cousin",
			from:     "/workspace/src/utils",
			to:       "/workspace/test/helpers",
			expected: "../../test/helpers",
		},
		{
			scenario: "Complex navigation",
			from:     "/a/b/c/d",
			to:       "/a/e/f",
			expected: "../../../e/f",
		},
		{
			scenario: "Relative paths",
			from:     "src/main",
			to:       "src/utils",
			expected: "../utils",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// Given: two paths
			from := MustVPath(s.from)
			to := MustVPath(s.to)

			// When: computing relative path
			rel, err := from.Rel(to)
			require.NoError(t, err)

			// Then: should produce expected relative path
			require.Equal(t, s.expected, rel.String())
		})
	}
}

func TestVPathBDD_CommonRoots(t *testing.T) {
	scenarios := []struct {
		scenario string
		paths    []string
		expected string
	}{
		{
			scenario: "Siblings share parent",
			paths:    []string{"/workspace/src", "/workspace/test"},
			expected: "/workspace",
		},
		{
			scenario: "Deep hierarchy with common ancestor",
			paths: []string{
				"/workspace/src/main.go",
				"/workspace/src/utils/helper.go",
				"/workspace/test/main_test.go",
			},
			expected: "/workspace",
		},
		{
			scenario: "Nested children share root",
			paths: []string{
				"/workspace/a/b/c",
				"/workspace/a/d/e",
				"/workspace/f",
			},
			expected: "/workspace",
		},
		{
			scenario: "No common root except filesystem root",
			paths:    []string{"/usr/bin", "/var/log", "/home/user"},
			expected: "/",
		},
		{
			scenario: "Identical paths",
			paths:    []string{"/workspace/src", "/workspace/src"},
			expected: "/workspace/src",
		},
		{
			scenario: "Single path",
			paths:    []string{"/workspace/src/main.go"},
			expected: "/workspace/src/main.go",
		},
		{
			scenario: "Relative paths with common prefix",
			paths:    []string{"src/main.go", "src/utils/helper.go", "src/test/main_test.go"},
			expected: "src",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// Given: multiple paths
			paths := make([]VPath, len(s.paths))
			for i, p := range s.paths {
				paths[i] = MustVPath(p)
			}

			// When: finding common root
			root, err := CommonRoot(paths)
			require.NoError(t, err)

			// Then: should find expected common root
			require.Equal(t, s.expected, root.String())
		})
	}
}

func TestVPathBDD_EdgeCases(t *testing.T) {
	scenarios := []struct {
		scenario    string
		description string
		operation   func() error
		shouldError bool
		errorMsg    string
	}{
		{
			scenario:    "Empty path rejected",
			description: "Parsing empty string should fail",
			operation: func() error {
				_, err := ParseVPath("")
				return err
			},
			shouldError: true,
			errorMsg:    "empty path",
		},
		{
			scenario:    "Backslashes rejected",
			description: "Backslashes are not allowed in VPath",
			operation: func() error {
				_, err := ParseVPath("a\\b")
				return err
			},
			shouldError: true,
			errorMsg:    "backslashes",
		},
		{
			scenario:    "Path escaping root rejected",
			description: "Cannot navigate above root",
			operation: func() error {
				_, err := ParseVPath("/../a")
				return err
			},
			shouldError: true,
			errorMsg:    "escapes root",
		},
		{
			scenario:    "Mixed absolute and relative in Rel",
			description: "Cannot compute relative path between absolute and relative",
			operation: func() error {
				from := MustVPath("/a/b")
				to := MustVPath("c/d")
				_, err := from.Rel(to)
				return err
			},
			shouldError: true,
			errorMsg:    "cannot compute relative path",
		},
		{
			scenario:    "Empty path list in CommonRoot",
			description: "Cannot find common root of empty list",
			operation: func() error {
				_, err := CommonRoot([]VPath{})
				return err
			},
			shouldError: true,
			errorMsg:    "empty path list",
		},
		{
			scenario:    "Mixed paths in CommonRoot",
			description: "Cannot find common root of mixed absolute/relative",
			operation: func() error {
				_, err := CommonRoot([]VPath{
					MustVPath("/a/b"),
					MustVPath("c/d"),
				})
				return err
			},
			shouldError: true,
			errorMsg:    "mixed absolute and relative",
		},
		{
			scenario:    "No common root for relative paths",
			description: "Relative paths with no common prefix should error",
			operation: func() error {
				_, err := CommonRoot([]VPath{
					MustVPath("a/b"),
					MustVPath("c/d"),
				})
				return err
			},
			shouldError: true,
			errorMsg:    "no common root found",
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			// When: performing operation
			err := s.operation()

			// Then: should match expected error behavior
			if s.shouldError {
				require.Error(t, err, s.description)
				require.Contains(t, err.Error(), s.errorMsg)
			} else {
				require.NoError(t, err, s.description)
			}
		})
	}
}

func TestVPathBDD_RealWorldScenarios(t *testing.T) {
	scenarios := []struct {
		scenario    string
		description string
		test        func(t *testing.T)
	}{
		{
			scenario:    "Workspace navigation",
			description: "Navigate between source and test directories",
			test: func(t *testing.T) {
				// Given: I am in the source directory
				srcPath := MustVPath("/workspace/src")

				// When: I navigate to a test file
				testPath, err := srcPath.Join("..", "test", "main_test.go")
				require.NoError(t, err)

				// Then: I should be in the test directory
				require.Equal(t, "/workspace/test/main_test.go", testPath.String())
				require.Equal(t, "/workspace/test", testPath.Dir().String())
			},
		},
		{
			scenario:    "Build artifact path resolution",
			description: "Resolve build artifacts with extensions",
			test: func(t *testing.T) {
				// Given: a source file path
				srcFile := MustVPath("/workspace/src/main.go")

				// When: determining output artifact
				dir := srcFile.Dir()
				stem := srcFile.Stem()
				artifactPath, err := dir.Join("..", "bin", stem)
				require.NoError(t, err)

				// Then: artifact should be in bin directory without extension
				require.Equal(t, "/workspace/bin/main", artifactPath.String())
			},
		},
		{
			scenario:    "Finding common project root",
			description: "Find project root from multiple file paths",
			test: func(t *testing.T) {
				// Given: multiple files in a project
				files := []VPath{
					MustVPath("/project/src/app/main.go"),
					MustVPath("/project/src/utils/helper.go"),
					MustVPath("/project/test/integration/api_test.go"),
					MustVPath("/project/README.md"),
				}

				// When: finding common root
				root, err := CommonRoot(files)
				require.NoError(t, err)

				// Then: should identify project directory
				require.Equal(t, "/project", root.String())
			},
		},
		{
			scenario:    "Relative import resolution",
			description: "Resolve relative imports in source code",
			test: func(t *testing.T) {
				// Given: I am in a source file
				currentFile := MustVPath("/workspace/src/app/handlers/user.go")

				// When: I need to import from utils
				utilsPath := MustVPath("/workspace/src/utils/validate.go")
				rel, err := currentFile.Dir().Rel(utilsPath.Dir())
				require.NoError(t, err)

				// Then: relative path should be calculated correctly
				require.Equal(t, "../../utils", rel.String())
			},
		},
	}

	for _, s := range scenarios {
		t.Run(s.scenario, func(t *testing.T) {
			s.test(t)
		})
	}
}
