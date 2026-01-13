package decorations

import (
	"testing"

	"github.com/finos/morphir/pkg/config"
	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestAttachedDistribution_Basic(t *testing.T) {
	// Create a simple distribution
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()
	attached := NewAttachedDistribution(lib, registry)

	// Verify distribution is set (check package name)
	dist := attached.Distribution()
	if dist == nil {
		t.Fatal("distribution is nil")
	}
	if !dist.PackageName().Equal(lib.PackageName()) {
		t.Error("package name mismatch")
	}

	if attached.Registry().Count() != 0 {
		t.Error("expected empty registry")
	}
}

func TestAttachedDistribution_WithRegistry(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry1 := decorationmodels.NewDecorationRegistry()
	attached1 := NewAttachedDistribution(lib, registry1)

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	decorationID := decorationmodels.DecorationID("test")
	value := []byte(`{"value": 42}`)

	registry2 := registry1.WithDecoration(nodePath, decorationID, value)
	attached2 := attached1.WithRegistry(registry2)

	// Original should be unchanged
	if attached1.HasDecoration(nodePath, decorationID) {
		t.Error("original attached distribution should not be modified")
	}

	// New one should have decoration
	if !attached2.HasDecoration(nodePath, decorationID) {
		t.Error("new attached distribution should have decoration")
	}
}

func TestLoadAndAttachDecorations_NoDecorations(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	projectConfig := config.ProjectSection{}
	attached, err := LoadAndAttachDecorations(lib, projectConfig, false)
	if err != nil {
		t.Fatalf("LoadAndAttachDecorations: %v", err)
	}

	if attached.Registry().Count() != 0 {
		t.Errorf("expected empty registry, got count %d", attached.Registry().Count())
	}
}
