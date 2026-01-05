package vfs

import "testing"

func TestParseVPath(t *testing.T) {
	t.Run("absolute path normalizes", func(t *testing.T) {
		path, err := ParseVPath("/a/./b//c")
		if err != nil {
			t.Fatalf("ParseVPath() error = %v", err)
		}
		if got := path.String(); got != "/a/b/c" {
			t.Fatalf("ParseVPath() = %q, want %q", got, "/a/b/c")
		}
	})

	t.Run("root path stays root", func(t *testing.T) {
		path, err := ParseVPath("/")
		if err != nil {
			t.Fatalf("ParseVPath() error = %v", err)
		}
		if got := path.String(); got != "/" {
			t.Fatalf("ParseVPath() = %q, want %q", got, "/")
		}
	})

	t.Run("relative path normalizes", func(t *testing.T) {
		path, err := ParseVPath("a/./b")
		if err != nil {
			t.Fatalf("ParseVPath() error = %v", err)
		}
		if got := path.String(); got != "a/b" {
			t.Fatalf("ParseVPath() = %q, want %q", got, "a/b")
		}
	})

	t.Run("rejects empty path", func(t *testing.T) {
		if _, err := ParseVPath(""); err == nil {
			t.Fatalf("ParseVPath() expected error")
		}
	})

	t.Run("rejects empty relative after normalization", func(t *testing.T) {
		if _, err := ParseVPath("./"); err == nil {
			t.Fatalf("ParseVPath() expected error")
		}
	})

	t.Run("rejects backslashes", func(t *testing.T) {
		if _, err := ParseVPath(`a\\b`); err == nil {
			t.Fatalf("ParseVPath() expected error")
		}
	})

	t.Run("rejects escape above root", func(t *testing.T) {
		if _, err := ParseVPath("/../a"); err == nil {
			t.Fatalf("ParseVPath() expected error")
		}
	})
}

func TestVPathJoin(t *testing.T) {
	base := MustVPath("/a/b")
	joined, err := base.Join("c", "d")
	if err != nil {
		t.Fatalf("Join() error = %v", err)
	}
	if got := joined.String(); got != "/a/b/c/d" {
		t.Fatalf("Join() = %q, want %q", got, "/a/b/c/d")
	}

	relative := MustVPath("a/b")
	relJoined, err := relative.Join("c")
	if err != nil {
		t.Fatalf("Join() error = %v", err)
	}
	if got := relJoined.String(); got != "a/b/c" {
		t.Fatalf("Join() = %q, want %q", got, "a/b/c")
	}
}

func TestMustVPath(t *testing.T) {
	if MustVPath("a/b").String() != "a/b" {
		t.Fatalf("MustVPath() did not return expected value")
	}

	defer func() {
		if recover() == nil {
			t.Fatalf("MustVPath() expected panic")
		}
	}()
	_ = MustVPath("")
}
