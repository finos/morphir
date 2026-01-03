package workspace

import (
	"path/filepath"
	"testing"
)

func TestHasProjectConfig(t *testing.T) {
	tests := []struct {
		name     string
		setup    func(t *testing.T, dir string)
		expected bool
	}{
		{
			name: "morphir.toml with project section",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[project]\nname = \"test\"")
			},
			expected: true,
		},
		{
			name: "morphir.toml without project section",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[morphir]\nversion = \"1.0\"")
			},
			expected: false,
		},
		{
			name: ".morphir/morphir.toml with project section",
			setup: func(t *testing.T, dir string) {
				createDir(t, filepath.Join(dir, ".morphir"))
				createFile(t, filepath.Join(dir, ".morphir", "morphir.toml"), "[project]\nname = \"test\"")
			},
			expected: true,
		},
		{
			name: "morphir.json exists",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.json"), "{}")
			},
			expected: true,
		},
		{
			name: "no config file",
			setup: func(t *testing.T, dir string) {
				// Empty directory
			},
			expected: false,
		},
		{
			name: "only README.md",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "README.md"), "# Project")
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			tt.setup(t, tmpDir)

			got := HasProjectConfig(tmpDir)
			if got != tt.expected {
				t.Errorf("HasProjectConfig() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestFindProjectConfig(t *testing.T) {
	tests := []struct {
		name         string
		setup        func(t *testing.T, dir string)
		wantFormat   string
		wantFound    bool
		wantFilename string // Just the filename, not full path
	}{
		{
			name: "morphir.toml with project section",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[project]\nname = \"test\"")
			},
			wantFormat:   "toml",
			wantFound:    true,
			wantFilename: "morphir.toml",
		},
		{
			name: ".morphir/morphir.toml with project section",
			setup: func(t *testing.T, dir string) {
				createDir(t, filepath.Join(dir, ".morphir"))
				createFile(t, filepath.Join(dir, ".morphir", "morphir.toml"), "[project]\nname = \"test\"")
			},
			wantFormat:   "toml",
			wantFound:    true,
			wantFilename: filepath.Join(".morphir", "morphir.toml"),
		},
		{
			name: "morphir.json exists",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.json"), "{}")
			},
			wantFormat:   "json",
			wantFound:    true,
			wantFilename: "morphir.json",
		},
		{
			name: "prefers morphir.toml over morphir.json",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[project]\nname = \"test\"")
				createFile(t, filepath.Join(dir, "morphir.json"), "{}")
			},
			wantFormat:   "toml",
			wantFound:    true,
			wantFilename: "morphir.toml",
		},
		{
			name: "no config file",
			setup: func(t *testing.T, dir string) {
				// Empty directory
			},
			wantFormat: "",
			wantFound:  false,
		},
		{
			name: "morphir.toml without project section",
			setup: func(t *testing.T, dir string) {
				createFile(t, filepath.Join(dir, "morphir.toml"), "[morphir]\nversion = \"1.0\"")
			},
			wantFormat: "",
			wantFound:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			tt.setup(t, tmpDir)

			path, format, found := FindProjectConfig(tmpDir)
			if found != tt.wantFound {
				t.Errorf("FindProjectConfig() found = %v, want %v", found, tt.wantFound)
			}
			if format != tt.wantFormat {
				t.Errorf("FindProjectConfig() format = %v, want %v", format, tt.wantFormat)
			}
			if tt.wantFound {
				expectedPath := filepath.Join(tmpDir, tt.wantFilename)
				if path != expectedPath {
					t.Errorf("FindProjectConfig() path = %v, want %v", path, expectedPath)
				}
			}
		})
	}
}

func TestDiscoverMembers_BasicGlob(t *testing.T) {
	// Create directory structure:
	// root/
	//   packages/
	//     pkg-a/
	//       morphir.toml (with [project])
	//     pkg-b/
	//       morphir.json
	//     not-a-project/
	//       README.md
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	createDir(t, filepath.Join(root, "packages", "pkg-b"))
	createFile(t, filepath.Join(root, "packages", "pkg-b", "morphir.json"), "{}")

	createDir(t, filepath.Join(root, "packages", "not-a-project"))
	createFile(t, filepath.Join(root, "packages", "not-a-project", "README.md"), "# Not a project")

	members, err := DiscoverMembers(root, []string{"packages/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d: %v", len(members), members)
	}

	// Check that paths are absolute and sorted
	expected := []string{
		filepath.Join(root, "packages", "pkg-a"),
		filepath.Join(root, "packages", "pkg-b"),
	}

	for i, exp := range expected {
		if i >= len(members) {
			t.Errorf("missing member at index %d: %v", i, exp)
			continue
		}
		if members[i] != exp {
			t.Errorf("member[%d] = %v, want %v", i, members[i], exp)
		}
	}
}

func TestDiscoverMembers_RecursiveGlob(t *testing.T) {
	// Create directory structure:
	// root/
	//   libs/
	//     core/
	//       morphir.toml (with [project])
	//     nested/
	//       deep/
	//         module/
	//           morphir.json
	root := t.TempDir()

	createDir(t, filepath.Join(root, "libs", "core"))
	createFile(t, filepath.Join(root, "libs", "core", "morphir.toml"), "[project]\nname = \"core\"")

	createDir(t, filepath.Join(root, "libs", "nested", "deep", "module"))
	createFile(t, filepath.Join(root, "libs", "nested", "deep", "module", "morphir.json"), "{}")

	members, err := DiscoverMembers(root, []string{"libs/**"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d: %v", len(members), members)
	}

	// Verify both are found (sorted order)
	expected := []string{
		filepath.Join(root, "libs", "core"),
		filepath.Join(root, "libs", "nested", "deep", "module"),
	}

	for i, exp := range expected {
		if i >= len(members) {
			t.Errorf("missing member at index %d: %v", i, exp)
			continue
		}
		if members[i] != exp {
			t.Errorf("member[%d] = %v, want %v", i, members[i], exp)
		}
	}
}

func TestDiscoverMembers_ExcludePatterns(t *testing.T) {
	// Create directory structure:
	// root/
	//   packages/
	//     pkg-a/
	//       morphir.toml (with [project])
	//     testdata/
	//       morphir.toml (with [project]) - should be excluded
	//     pkg-b/
	//       testdata/
	//         morphir.json - should be excluded
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	createDir(t, filepath.Join(root, "packages", "testdata"))
	createFile(t, filepath.Join(root, "packages", "testdata", "morphir.toml"), "[project]\nname = \"testdata\"")

	createDir(t, filepath.Join(root, "packages", "pkg-b", "testdata"))
	createFile(t, filepath.Join(root, "packages", "pkg-b", "testdata", "morphir.json"), "{}")

	members, err := DiscoverMembers(root, []string{"packages/**"}, []string{"**/testdata", "**/testdata/**"})
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 1 {
		t.Errorf("expected 1 member, got %d: %v", len(members), members)
	}

	expected := filepath.Join(root, "packages", "pkg-a")
	if len(members) > 0 && members[0] != expected {
		t.Errorf("member[0] = %v, want %v", members[0], expected)
	}
}

func TestDiscoverMembers_MultiplePatterns(t *testing.T) {
	// Create directory structure:
	// root/
	//   packages/
	//     pkg-a/
	//       morphir.toml
	//   libs/
	//     lib-a/
	//       morphir.json
	//   apps/
	//     app-a/
	//       morphir.toml
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	createDir(t, filepath.Join(root, "libs", "lib-a"))
	createFile(t, filepath.Join(root, "libs", "lib-a", "morphir.json"), "{}")

	createDir(t, filepath.Join(root, "apps", "app-a"))
	createFile(t, filepath.Join(root, "apps", "app-a", "morphir.toml"), "[project]\nname = \"app-a\"")

	members, err := DiscoverMembers(root, []string{"packages/*", "libs/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d: %v", len(members), members)
	}

	// apps/app-a should NOT be found since we only search packages/* and libs/*
	for _, member := range members {
		if filepath.Base(filepath.Dir(member)) == "apps" {
			t.Errorf("unexpected member from apps/: %v", member)
		}
	}
}

func TestDiscoverMembers_SingleCharWildcard(t *testing.T) {
	// Create directory structure:
	// root/
	//   pkg1/
	//     morphir.toml
	//   pkg2/
	//     morphir.toml
	//   pkga/
	//     morphir.toml - should NOT match pkg?
	root := t.TempDir()

	createDir(t, filepath.Join(root, "pkg1"))
	createFile(t, filepath.Join(root, "pkg1", "morphir.toml"), "[project]\nname = \"pkg1\"")

	createDir(t, filepath.Join(root, "pkg2"))
	createFile(t, filepath.Join(root, "pkg2", "morphir.toml"), "[project]\nname = \"pkg2\"")

	createDir(t, filepath.Join(root, "pkga"))
	createFile(t, filepath.Join(root, "pkga", "morphir.toml"), "[project]\nname = \"pkga\"")

	// ? matches any single character
	members, err := DiscoverMembers(root, []string{"pkg?"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 3 {
		t.Errorf("expected 3 members, got %d: %v", len(members), members)
	}
}

func TestDiscoverMembers_CharacterClass(t *testing.T) {
	// Create directory structure:
	// root/
	//   pkg-a/
	//     morphir.toml
	//   pkg-b/
	//     morphir.toml
	//   pkg-c/
	//     morphir.toml - should NOT match [ab]
	root := t.TempDir()

	createDir(t, filepath.Join(root, "pkg-a"))
	createFile(t, filepath.Join(root, "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	createDir(t, filepath.Join(root, "pkg-b"))
	createFile(t, filepath.Join(root, "pkg-b", "morphir.toml"), "[project]\nname = \"pkg-b\"")

	createDir(t, filepath.Join(root, "pkg-c"))
	createFile(t, filepath.Join(root, "pkg-c", "morphir.toml"), "[project]\nname = \"pkg-c\"")

	members, err := DiscoverMembers(root, []string{"pkg-[ab]"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 2 {
		t.Errorf("expected 2 members, got %d: %v", len(members), members)
	}

	// pkg-c should NOT be found
	for _, member := range members {
		if filepath.Base(member) == "pkg-c" {
			t.Errorf("unexpected member pkg-c: %v", member)
		}
	}
}

func TestDiscoverMembers_EmptyPatterns(t *testing.T) {
	root := t.TempDir()

	members, err := DiscoverMembers(root, nil, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 0 {
		t.Errorf("expected 0 members for empty patterns, got %d", len(members))
	}
}

func TestDiscoverMembers_NoMatches(t *testing.T) {
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages"))

	members, err := DiscoverMembers(root, []string{"nonexistent/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 0 {
		t.Errorf("expected 0 members, got %d", len(members))
	}
}

func TestDiscoverMembers_SortedOutput(t *testing.T) {
	root := t.TempDir()

	// Create in non-alphabetical order
	for _, name := range []string{"zeta", "alpha", "beta", "gamma"} {
		createDir(t, filepath.Join(root, "packages", name))
		createFile(t, filepath.Join(root, "packages", name, "morphir.toml"), "[project]\nname = \""+name+"\"")
	}

	members, err := DiscoverMembers(root, []string{"packages/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 4 {
		t.Fatalf("expected 4 members, got %d", len(members))
	}

	// Verify sorted order
	expected := []string{"alpha", "beta", "gamma", "zeta"}
	for i, exp := range expected {
		if filepath.Base(members[i]) != exp {
			t.Errorf("member[%d] = %v, want name %v", i, filepath.Base(members[i]), exp)
		}
	}
}

func TestDiscoverMembers_AbsolutePaths(t *testing.T) {
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	members, err := DiscoverMembers(root, []string{"packages/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 1 {
		t.Fatalf("expected 1 member, got %d", len(members))
	}

	if !filepath.IsAbs(members[0]) {
		t.Errorf("expected absolute path, got %v", members[0])
	}
}

func TestDiscoverMembers_HiddenMorphirToml(t *testing.T) {
	// Create directory structure:
	// root/
	//   packages/
	//     pkg-a/
	//       .morphir/
	//         morphir.toml (with [project])
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a", ".morphir"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", ".morphir", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	members, err := DiscoverMembers(root, []string{"packages/*"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 1 {
		t.Errorf("expected 1 member, got %d: %v", len(members), members)
	}
}

func TestDiscoverMembers_InvalidRoot(t *testing.T) {
	_, err := DiscoverMembers("/nonexistent/path", []string{"packages/*"}, nil)
	if err == nil {
		t.Fatal("expected error for non-existent root")
	}
}

func TestDiscoverMembers_DuplicatesRemoved(t *testing.T) {
	// Create directory that matches multiple patterns
	root := t.TempDir()

	createDir(t, filepath.Join(root, "packages", "pkg-a"))
	createFile(t, filepath.Join(root, "packages", "pkg-a", "morphir.toml"), "[project]\nname = \"pkg-a\"")

	// Both patterns could match the same directory
	members, err := DiscoverMembers(root, []string{"packages/*", "packages/pkg-a"}, nil)
	if err != nil {
		t.Fatalf("DiscoverMembers: unexpected error: %v", err)
	}

	if len(members) != 1 {
		t.Errorf("expected 1 member (duplicates removed), got %d: %v", len(members), members)
	}
}
