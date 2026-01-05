package vfs

import "testing"

func TestParseGlob(t *testing.T) {
	t.Run("accepts simple glob", func(t *testing.T) {
		glob, err := ParseGlob("**/*.elm")
		if err != nil {
			t.Fatalf("ParseGlob() error = %v", err)
		}
		if got := glob.String(); got != "**/*.elm" {
			t.Fatalf("ParseGlob() = %q, want %q", got, "**/*.elm")
		}
	})

	t.Run("rejects empty glob", func(t *testing.T) {
		if _, err := ParseGlob(""); err == nil {
			t.Fatalf("ParseGlob() expected error")
		}
	})

	t.Run("rejects backslashes", func(t *testing.T) {
		if _, err := ParseGlob(`**\\*.elm`); err == nil {
			t.Fatalf("ParseGlob() expected error")
		}
	})
}

func TestMustGlob(t *testing.T) {
	if MustGlob("**/*.elm").String() != "**/*.elm" {
		t.Fatalf("MustGlob() did not return expected value")
	}

	defer func() {
		if recover() == nil {
			t.Fatalf("MustGlob() expected panic")
		}
	}()
	_ = MustGlob("")
}
