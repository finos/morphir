package morphirfs

import (
	"strings"
	"testing"
)

func TestFS_WorkingDir_WhenNoneExplicitlyProvided(t *testing.T) {
	fs, err := New()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	wd, err := fs.WorkingDir()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !strings.Contains(string(wd), "morphir") {
		t.Fatalf("expected working directory to contain 'morphir', got %v", wd)
	}
}
