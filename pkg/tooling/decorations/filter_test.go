package decorations

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestFilterDecorationsForNode(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dec1 := decorationmodels.DecorationID("decoration1")
	dec2 := decorationmodels.DecorationID("decoration2")
	dec3 := decorationmodels.DecorationID("decoration3")

	value1 := json.RawMessage(`{"type": "one"}`)
	value2 := json.RawMessage(`{"type": "two"}`)
	value3 := json.RawMessage(`{"type": "three"}`)

	registry = registry.WithDecoration(nodePath, dec1, value1)
	registry = registry.WithDecoration(nodePath, dec2, value2)
	registry = registry.WithDecoration(nodePath, dec3, value3)

	attached := NewAttachedDistribution(lib, registry)

	// Filter by specific IDs
	options := FilterOptions{
		DecorationIDs: []decorationmodels.DecorationID{dec1, dec3},
	}

	filtered := attached.FilterDecorationsForNode(nodePath, options)
	if len(filtered) != 2 {
		t.Fatalf("expected 2 decorations, got %d", len(filtered))
	}

	if _, found := filtered[dec1]; !found {
		t.Error("expected decoration1 in filtered results")
	}
	if _, found := filtered[dec3]; !found {
		t.Error("expected decoration3 in filtered results")
	}
	if _, found := filtered[dec2]; found {
		t.Error("decoration2 should be filtered out")
	}
}

func TestFilterDecorationsForNode_NoFilter(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dec1 := decorationmodels.DecorationID("decoration1")
	dec2 := decorationmodels.DecorationID("decoration2")

	registry = registry.WithDecoration(nodePath, dec1, json.RawMessage(`{"type": "one"}`))
	registry = registry.WithDecoration(nodePath, dec2, json.RawMessage(`{"type": "two"}`))

	attached := NewAttachedDistribution(lib, registry)

	// No filter - should return all
	options := FilterOptions{
		DecorationIDs: nil, // Empty filter
	}

	filtered := attached.FilterDecorationsForNode(nodePath, options)
	if len(filtered) != 2 {
		t.Fatalf("expected 2 decorations, got %d", len(filtered))
	}
}

func TestGetAllNodesWithDecorations(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()

	nodePath1 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	nodePath2 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"baz"}),
	))

	decorationID := decorationmodels.DecorationID("test")

	registry = registry.WithDecoration(nodePath1, decorationID, json.RawMessage(`{"value": 1}`))
	registry = registry.WithDecoration(nodePath2, decorationID, json.RawMessage(`{"value": 2}`))

	attached := NewAttachedDistribution(lib, registry)

	nodes := attached.GetAllNodesWithDecorations()
	if len(nodes) != 2 {
		t.Fatalf("expected 2 nodes, got %d", len(nodes))
	}
}

func TestGetAllNodesWithDecoration(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()

	nodePath1 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	nodePath2 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"baz"}),
	))

	dec1 := decorationmodels.DecorationID("decoration1")
	dec2 := decorationmodels.DecorationID("decoration2")

	registry = registry.WithDecoration(nodePath1, dec1, json.RawMessage(`{"value": 1}`))
	registry = registry.WithDecoration(nodePath1, dec2, json.RawMessage(`{"value": 2}`))
	registry = registry.WithDecoration(nodePath2, dec1, json.RawMessage(`{"value": 3}`))

	attached := NewAttachedDistribution(lib, registry)

	// Get nodes with decoration1
	nodes := attached.GetAllNodesWithDecoration(dec1)
	if len(nodes) != 2 {
		t.Fatalf("expected 2 nodes with decoration1, got %d", len(nodes))
	}

	// Get nodes with decoration2
	nodes = attached.GetAllNodesWithDecoration(dec2)
	if len(nodes) != 1 {
		t.Fatalf("expected 1 node with decoration2, got %d", len(nodes))
	}
}

func TestListDecorationIDs(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dec1 := decorationmodels.DecorationID("decoration1")
	dec2 := decorationmodels.DecorationID("decoration2")

	registry = registry.WithDecoration(nodePath, dec1, json.RawMessage(`{"value": 1}`))
	registry = registry.WithDecoration(nodePath, dec2, json.RawMessage(`{"value": 2}`))

	attached := NewAttachedDistribution(lib, registry)

	ids := attached.ListDecorationIDs()
	if len(ids) != 2 {
		t.Fatalf("expected 2 decoration IDs, got %d", len(ids))
	}

	// Check both IDs are present
	idSet := make(map[decorationmodels.DecorationID]bool)
	for _, id := range ids {
		idSet[id] = true
	}

	if !idSet[dec1] {
		t.Error("expected decoration1 in list")
	}
	if !idSet[dec2] {
		t.Error("expected decoration2 in list")
	}
}

func TestGetDecorationsByID(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()

	nodePath1 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	nodePath2 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"baz"}),
	))

	dec1 := decorationmodels.DecorationID("decoration1")
	dec2 := decorationmodels.DecorationID("decoration2")

	value1a := json.RawMessage(`{"value": "a"}`)
	value1b := json.RawMessage(`{"value": "b"}`)
	value2 := json.RawMessage(`{"value": "c"}`)

	registry = registry.WithDecoration(nodePath1, dec1, value1a)
	registry = registry.WithDecoration(nodePath2, dec1, value1b)
	registry = registry.WithDecoration(nodePath1, dec2, value2)

	attached := NewAttachedDistribution(lib, registry)

	// Get all decoration1 values
	byID := attached.GetDecorationsByID(dec1)
	if len(byID) != 2 {
		t.Fatalf("expected 2 nodes with decoration1, got %d", len(byID))
	}

	if string(byID[nodePath1.String()]) != string(value1a) {
		t.Error("value mismatch for nodePath1")
	}
	if string(byID[nodePath2.String()]) != string(value1b) {
		t.Error("value mismatch for nodePath2")
	}
}

func TestCountDecorations(t *testing.T) {
	lib := ir.NewLibrary(
		ir.PathFromString("My.Package"),
		nil,
		ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]](),
	)

	registry := decorationmodels.NewDecorationRegistry()

	nodePath1 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	nodePath2 := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"baz"}),
	))

	decorationID := decorationmodels.DecorationID("test")

	registry = registry.WithDecoration(nodePath1, decorationID, json.RawMessage(`{"value": 1}`))
	registry = registry.WithDecoration(nodePath2, decorationID, json.RawMessage(`{"value": 2}`))

	attached := NewAttachedDistribution(lib, registry)

	if attached.CountDecorations() != 2 {
		t.Errorf("CountDecorations: got %d, want 2", attached.CountDecorations())
	}

	if attached.CountDecorationsForNode(nodePath1) != 1 {
		t.Errorf("CountDecorationsForNode: got %d, want 1", attached.CountDecorationsForNode(nodePath1))
	}
}
