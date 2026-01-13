package decorations

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestNewDecorationIR(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("Test.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	irPath := "test-ir.json"
	decIR := NewDecorationIR(lib, irPath)

	if decIR.IRPath() != irPath {
		t.Errorf("IRPath: got %q, want %q", decIR.IRPath(), irPath)
	}

	dist := decIR.Distribution()
	if dist == nil {
		t.Error("expected distribution to be non-nil")
	}

	lib2, ok := dist.(ir.Library)
	if !ok {
		t.Error("expected distribution to be a Library")
	}

	if !lib2.PackageName().Equal(ir.PathFromString("Test.Package")) {
		t.Error("package name mismatch")
	}
}

func TestDecorationIR_Distribution(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	decIR := NewDecorationIR(lib, "test.json")

	dist := decIR.Distribution()
	if dist == nil {
		t.Error("expected distribution to be non-nil")
	}

	// Verify it's the same distribution
	lib2 := dist.(ir.Library)
	if !lib2.PackageName().Equal(lib.PackageName()) {
		t.Error("distribution mismatch")
	}
}

func TestDecorationIR_IRPath(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("Test"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	testCases := []string{
		"test.json",
		"/absolute/path/to/ir.json",
		"relative/path/ir.json",
		"",
	}

	for _, tc := range testCases {
		decIR := NewDecorationIR(lib, tc)
		if decIR.IRPath() != tc {
			t.Errorf("IRPath: got %q, want %q", decIR.IRPath(), tc)
		}
	}
}
