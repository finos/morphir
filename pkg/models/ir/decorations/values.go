package decorations

import (
	"encoding/json"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// DecorationValues represents a collection of decoration values keyed by NodePath strings.
//
// Decoration values are stored in JSON files where:
//   - Keys are NodePath strings (e.g., "My.Package:Foo:bar" for FQName, "My.Package:Foo" for modules)
//   - Values are Morphir IR values encoded as JSON
//
// This type maintains immutability by returning defensive copies.
// We use string keys (NodePath.String()) because NodePath contains slices and cannot be used as map keys directly.
type DecorationValues struct {
	values map[string]json.RawMessage
}

// NewDecorationValues creates a new DecorationValues from a map.
// The map is defensively copied to ensure immutability.
func NewDecorationValues(values map[string]json.RawMessage) DecorationValues {
	var copied map[string]json.RawMessage
	if len(values) > 0 {
		copied = make(map[string]json.RawMessage, len(values))
		for k, v := range values {
			// Copy the JSON raw message
			vCopy := make(json.RawMessage, len(v))
			copy(vCopy, v)
			copied[k] = vCopy
		}
	}
	return DecorationValues{values: copied}
}

// EmptyDecorationValues returns an empty DecorationValues.
func EmptyDecorationValues() DecorationValues {
	return DecorationValues{values: nil}
}

// Get returns the decoration value for the given NodePath, or nil if not found.
// Returns a defensive copy of the JSON raw message.
func (d DecorationValues) Get(nodePath ir.NodePath) (json.RawMessage, bool) {
	if d.values == nil {
		return nil, false
	}
	key := nodePath.String()
	val, ok := d.values[key]
	if !ok {
		return nil, false
	}
	// Return defensive copy
	valCopy := make(json.RawMessage, len(val))
	copy(valCopy, val)
	return valCopy, true
}

// All returns all decoration values as a map keyed by NodePath strings.
// Returns a defensive copy of the map and all values.
func (d DecorationValues) All() map[string]json.RawMessage {
	if d.values == nil {
		return nil
	}
	result := make(map[string]json.RawMessage, len(d.values))
	for k, v := range d.values {
		// Copy the JSON raw message
		vCopy := make(json.RawMessage, len(v))
		copy(vCopy, v)
		result[k] = vCopy
	}
	return result
}

// Count returns the number of decoration values.
func (d DecorationValues) Count() int {
	if d.values == nil {
		return 0
	}
	return len(d.values)
}

// Has returns true if a decoration value exists for the given NodePath.
func (d DecorationValues) Has(nodePath ir.NodePath) bool {
	if d.values == nil {
		return false
	}
	key := nodePath.String()
	_, ok := d.values[key]
	return ok
}

// WithValue returns a new DecorationValues with the given value added/updated.
// This maintains immutability by creating a new instance.
func (d DecorationValues) WithValue(nodePath ir.NodePath, value json.RawMessage) DecorationValues {
	newValues := make(map[string]json.RawMessage)

	// Copy existing values
	if d.values != nil {
		for k, v := range d.values {
			vCopy := make(json.RawMessage, len(v))
			copy(vCopy, v)
			newValues[k] = vCopy
		}
	}

	// Add/update the new value
	key := nodePath.String()
	valueCopy := make(json.RawMessage, len(value))
	copy(valueCopy, value)
	newValues[key] = valueCopy

	return DecorationValues{values: newValues}
}

// WithoutValue returns a new DecorationValues with the given NodePath removed.
// This maintains immutability by creating a new instance.
func (d DecorationValues) WithoutValue(nodePath ir.NodePath) DecorationValues {
	if d.values == nil {
		return d
	}
	key := nodePath.String()
	if _, ok := d.values[key]; !ok {
		return d
	}

	newValues := make(map[string]json.RawMessage, len(d.values)-1)
	for k, v := range d.values {
		if k == key {
			continue
		}
		vCopy := make(json.RawMessage, len(v))
		copy(vCopy, v)
		newValues[k] = vCopy
	}

	return DecorationValues{values: newValues}
}
