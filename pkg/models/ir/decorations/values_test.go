package decorations

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestNewDecorationValues(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
		"My.Package:Foo:baz": json.RawMessage(`{"test": "value2"}`),
	}

	dv := NewDecorationValues(values)

	assert.Equal(t, 2, dv.Count())

	// Verify immutability - original map should not be affected
	values["new"] = json.RawMessage(`{}`)
	assert.Equal(t, 2, dv.Count(), "NewDecorationValues should create defensive copy")
}

func TestEmptyDecorationValues(t *testing.T) {
	dv := EmptyDecorationValues()

	assert.Equal(t, 0, dv.Count())

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	assert.False(t, dv.Has(nodePath), "expected no values for empty DecorationValues")
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
	require.True(t, found, "expected value to be found")
	assert.Equal(t, `{"test": "value"}`, string(val))

	// Test defensive copy
	val[0] = 'X'
	val2, _ := dv.Get(nodePath)
	assert.Equal(t, `{"test": "value"}`, string(val2), "Get should return defensive copy")

	// Test not found
	missingPath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"missing"}),
	))
	_, found = dv.Get(missingPath)
	assert.False(t, found, "expected value not to be found")
}

func TestDecorationValues_Get_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	_, found := dv.Get(nodePath)
	assert.False(t, found, "expected no value for empty DecorationValues")
}

func TestDecorationValues_All(t *testing.T) {
	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{"test": "value"}`),
		"My.Package:Foo:baz": json.RawMessage(`{"test": "value2"}`),
	}
	dv := NewDecorationValues(values)

	all := dv.All()
	assert.Len(t, all, 2)

	// Verify defensive copy
	all["new"] = json.RawMessage(`{}`)
	assert.Equal(t, 2, dv.Count(), "All should return defensive copy")
}

func TestDecorationValues_All_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	all := dv.All()
	assert.Nil(t, all)
}

func TestDecorationValues_Count(t *testing.T) {
	dv := EmptyDecorationValues()
	assert.Equal(t, 0, dv.Count())

	values := map[string]json.RawMessage{
		"My.Package:Foo:bar": json.RawMessage(`{}`),
	}
	dv = NewDecorationValues(values)
	assert.Equal(t, 1, dv.Count())
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

	assert.True(t, dv.Has(nodePath))

	missingPath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"missing"}),
	))
	assert.False(t, dv.Has(missingPath))
}

func TestDecorationValues_Has_Empty(t *testing.T) {
	dv := EmptyDecorationValues()

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	assert.False(t, dv.Has(nodePath), "expected Has to return false for empty DecorationValues")
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

	assert.Equal(t, 0, dv.Count(), "original DecorationValues should be unchanged")
	assert.Equal(t, 1, dv2.Count())
	assert.True(t, dv2.Has(nodePath), "expected value to be present")

	val, found := dv2.Get(nodePath)
	require.True(t, found, "expected value to be found")
	assert.Equal(t, string(value), string(val))
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
	assert.Equal(t, `{"test": "old"}`, string(val), "original DecorationValues should be unchanged")

	// New should have updated value
	val2, _ := dv2.Get(nodePath)
	assert.Equal(t, `{"test": "new"}`, string(val2))
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
	assert.Equal(t, 2, dv.Count(), "original DecorationValues should be unchanged")

	// New should have one less
	assert.Equal(t, 1, dv2.Count())
	assert.False(t, dv2.Has(nodePath), "expected value to be removed")
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
	assert.Equal(t, 1, dv2.Count())
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
	assert.Equal(t, 0, dv2.Count(), "expected no change for empty DecorationValues")
}
