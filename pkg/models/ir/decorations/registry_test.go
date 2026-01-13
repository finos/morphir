package decorations

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestDecorationRegistry_Empty(t *testing.T) {
	registry := EmptyDecorationRegistry()

	if registry.Count() != 0 {
		t.Errorf("Count: got %d, want 0", registry.Count())
	}

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	if registry.HasAnyDecoration(nodePath) {
		t.Error("expected no decorations for empty registry")
	}

	_, found := registry.GetDecoration(nodePath, DecorationID("test"))
	if found {
		t.Error("expected no decoration found")
	}
}

func TestDecorationRegistry_WithDecoration(t *testing.T) {
	registry := NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	decorationID := DecorationID("myDecoration")
	value := json.RawMessage(`{"test": "value"}`)

	registry = registry.WithDecoration(nodePath, decorationID, value)

	if !registry.HasDecoration(nodePath, decorationID) {
		t.Error("expected decoration to be present")
	}

	got, found := registry.GetDecoration(nodePath, decorationID)
	if !found {
		t.Fatal("expected decoration to be found")
	}

	if string(got) != string(value) {
		t.Errorf("value: got %q, want %q", string(got), string(value))
	}
}

func TestDecorationRegistry_MultipleDecorations(t *testing.T) {
	registry := NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dec1 := DecorationID("decoration1")
	dec2 := DecorationID("decoration2")
	value1 := json.RawMessage(`{"type": "one"}`)
	value2 := json.RawMessage(`{"type": "two"}`)

	registry = registry.WithDecoration(nodePath, dec1, value1)
	registry = registry.WithDecoration(nodePath, dec2, value2)

	if registry.Count() != 2 {
		t.Errorf("Count: got %d, want 2", registry.Count())
	}

	allDecs := registry.GetDecorationsForNode(nodePath)
	if len(allDecs) != 2 {
		t.Fatalf("GetDecorationsForNode: got %d decorations, want 2", len(allDecs))
	}

	if string(allDecs[dec1]) != string(value1) {
		t.Errorf("decoration1 value mismatch")
	}
	if string(allDecs[dec2]) != string(value2) {
		t.Errorf("decoration2 value mismatch")
	}
}

func TestDecorationRegistry_WithoutDecoration(t *testing.T) {
	registry := NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	decorationID := DecorationID("myDecoration")
	value := json.RawMessage(`{"test": "value"}`)

	registry = registry.WithDecoration(nodePath, decorationID, value)
	registry = registry.WithoutDecoration(nodePath, decorationID)

	if registry.HasDecoration(nodePath, decorationID) {
		t.Error("expected decoration to be removed")
	}

	if registry.Count() != 0 {
		t.Errorf("Count: got %d, want 0", registry.Count())
	}
}

func TestDecorationRegistry_Immutability(t *testing.T) {
	registry1 := NewDecorationRegistry()
	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	decorationID := DecorationID("myDecoration")
	value := json.RawMessage(`{"test": "value"}`)

	registry2 := registry1.WithDecoration(nodePath, decorationID, value)

	// Original registry should be unchanged
	if registry1.HasDecoration(nodePath, decorationID) {
		t.Error("original registry should not be modified")
	}

	// New registry should have the decoration
	if !registry2.HasDecoration(nodePath, decorationID) {
		t.Error("new registry should have the decoration")
	}
}

func TestFromDecorationValues(t *testing.T) {
	decorationID := DecorationID("myDecoration")
	values := NewDecorationValues(map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"value": 1}`),
		"My.Package:Foo:baz": json.RawMessage(`{"value": 2}`),
	})

	registry := FromDecorationValues(decorationID, values)

	if registry.Count() != 2 {
		t.Errorf("Count: got %d, want 2", registry.Count())
	}

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

	if !registry.HasDecoration(nodePath1, decorationID) {
		t.Error("expected decoration for nodePath1")
	}

	if !registry.HasDecoration(nodePath2, decorationID) {
		t.Error("expected decoration for nodePath2")
	}
}

func TestMerge(t *testing.T) {
	registry1 := NewDecorationRegistry()
	registry2 := NewDecorationRegistry()

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

	dec1 := DecorationID("decoration1")
	dec2 := DecorationID("decoration2")
	value1 := json.RawMessage(`{"type": "one"}`)
	value2 := json.RawMessage(`{"type": "two"}`)

	registry1 = registry1.WithDecoration(nodePath1, dec1, value1)
	registry2 = registry2.WithDecoration(nodePath2, dec2, value2)

	merged := Merge(registry1, registry2)

	if merged.Count() != 2 {
		t.Errorf("Count: got %d, want 2", merged.Count())
	}

	if !merged.HasDecoration(nodePath1, dec1) {
		t.Error("expected decoration1 in merged registry")
	}

	if !merged.HasDecoration(nodePath2, dec2) {
		t.Error("expected decoration2 in merged registry")
	}
}
