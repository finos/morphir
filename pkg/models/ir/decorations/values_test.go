package decorations

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestNewDecorationValues(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
		"My.Package:Foo:baz": json.RawMessage(`{"test": "value2"}`),
	}

	dv := NewDecorationValues(values)

	if dv.Count() != 2 {
		t.Errorf("Count: got %d, want 2", dv.Count())
	}

	// Verify immutability - original map should not be affected
	values["new"] = json.RawMessage(`{}`)
	if dv.Count() != 2 {
		t.Error("NewDecorationValues should create defensive copy")
	}
}

func TestEmptyDecorationValues(t *testing.T) {
	dv := EmptyDecorationValues()

	if dv.Count() != 0 {
		t.Errorf("Count: got %d, want 0", dv.Count())
	}

	if dv.Has(ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))) {
		t.Error("expected no values for empty DecorationValues")
	}
}

func TestDecorationValues_Get(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
	}
	dv := NewDecorationValues(values)

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	val, found := dv.Get(nodePath)
	if !found {
		t.Error("expected value to be found")
	}
	if string(val) != `{"test": "value"}` {
		t.Errorf("Get: got %q, want %q", string(val), `{"test": "value"}`)
	}

	// Test defensive copy
	val[0] = 'X'
	val2, _ := dv.Get(nodePath)
	if string(val2) != `{"test": "value"}` {
		t.Error("Get should return defensive copy")
	}

	// Test not found
	missingPath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"missing"}),
	))
	_, found = dv.Get(missingPath)
	if found {
		t.Error("expected value not to be found")
	}
}

func TestDecorationValues_Get_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	_, found := dv.Get(nodePath)
	if found {
		t.Error("expected no value for empty DecorationValues")
	}
}

func TestDecorationValues_All(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
		"My.Package:Foo:baz": json.RawMessage(`{"test": "value2"}`),
	}
	dv := NewDecorationValues(values)

	all := dv.All()
	if len(all) != 2 {
		t.Errorf("All: got %d items, want 2", len(all))
	}

	// Verify defensive copy
	all["new"] = json.RawMessage(`{}`)
	if dv.Count() != 2 {
		t.Error("All should return defensive copy")
	}
}

func TestDecorationValues_All_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	all := dv.All()
	if all != nil {
		t.Errorf("All: got %v, want nil", all)
	}
}

func TestDecorationValues_Count(t *testing.T) {
	dv := EmptyDecorationValues()
	if dv.Count() != 0 {
		t.Errorf("Count (empty): got %d, want 0", dv.Count())
	}

	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{}`),
	}
	dv = NewDecorationValues(values)
	if dv.Count() != 1 {
		t.Errorf("Count: got %d, want 1", dv.Count())
	}
}

func TestDecorationValues_Has(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
	}
	dv := NewDecorationValues(values)

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	if !dv.Has(nodePath) {
		t.Error("expected Has to return true")
	}

	missingPath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"missing"}),
	))
	if dv.Has(missingPath) {
		t.Error("expected Has to return false")
	}
}

func TestDecorationValues_Has_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	if dv.Has(nodePath) {
		t.Error("expected Has to return false for empty DecorationValues")
	}
}

func TestDecorationValues_WithValue(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	value := json.RawMessage(`{"test": "value"}`)
	dv2 := dv.WithValue(nodePath, value)

	if dv.Count() != 0 {
		t.Error("original DecorationValues should be unchanged")
	}

	if dv2.Count() != 1 {
		t.Errorf("Count: got %d, want 1", dv2.Count())
	}

	if !dv2.Has(nodePath) {
		t.Error("expected value to be present")
	}

	val, found := dv2.Get(nodePath)
	if !found {
		t.Error("expected value to be found")
	}
	if string(val) != string(value) {
		t.Errorf("Get: got %q, want %q", string(val), string(value))
	}
}

func TestDecorationValues_WithValue_Update(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "old"}`),
	}
	dv := NewDecorationValues(values)

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	newValue := json.RawMessage(`{"test": "new"}`)
	dv2 := dv.WithValue(nodePath, newValue)

	// Original should be unchanged
	val, _ := dv.Get(nodePath)
	if string(val) != `{"test": "old"}` {
		t.Error("original DecorationValues should be unchanged")
	}

	// New should have updated value
	val2, _ := dv2.Get(nodePath)
	if string(val2) != `{"test": "new"}` {
		t.Errorf("Get: got %q, want %q", string(val2), `{"test": "new"}`)
	}
}

func TestDecorationValues_WithoutValue(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
		"My.Package:Foo:baz": json.RawMessage(`{"test": "value2"}`),
	}
	dv := NewDecorationValues(values)

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dv2 := dv.WithoutValue(nodePath)

	// Original should be unchanged
	if dv.Count() != 2 {
		t.Error("original DecorationValues should be unchanged")
	}

	// New should have one less
	if dv2.Count() != 1 {
		t.Errorf("Count: got %d, want 1", dv2.Count())
	}

	if dv2.Has(nodePath) {
		t.Error("expected value to be removed")
	}
}

func TestDecorationValues_WithoutValue_NotExists(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
	}
	dv := NewDecorationValues(values)

	missingPath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"missing"}),
	))

	dv2 := dv.WithoutValue(missingPath)

	// Should return same instance (no change)
	if dv2.Count() != 1 {
		t.Errorf("Count: got %d, want 1", dv2.Count())
	}
}

func TestDecorationValues_WithoutValue_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	dv2 := dv.WithoutValue(nodePath)

	// Should return same instance
	if dv2.Count() != 0 {
		t.Error("expected no change for empty DecorationValues")
	}
}
