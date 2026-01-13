package decorations

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

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

	assert.Equal(t, irPath, decIR.IRPath())

	dist := decIR.Distribution()
	require.NotNil(t, dist, "expected distribution to be non-nil")

	lib2, ok := dist.(ir.Library)
	require.True(t, ok, "expected distribution to be a Library")

	assert.True(t, lib2.PackageName().Equal(ir.PathFromString("Test.Package")), "package name mismatch")
}

func TestDecorationIR_Distribution(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	decIR := NewDecorationIR(lib, "test.json")

	dist := decIR.Distribution()
	require.NotNil(t, dist, "expected distribution to be non-nil")

	// Verify it's the same distribution
	lib2 := dist.(ir.Library)
	assert.True(t, lib2.PackageName().Equal(lib.PackageName()), "distribution mismatch")
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
		assert.Equal(t, tc, decIR.IRPath())
	}
}
