package decorations

import (
	"encoding/json"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// DecorationID is an identifier for a decoration type (e.g., "myDecoration" from morphir.json).
type DecorationID string

// DecorationRegistry maintains a mapping of decorations to IR nodes.
//
// The registry maps:
//   - NodePath (string) → DecorationID → DecorationValue (json.RawMessage)
//
// This allows multiple decorations to be attached to the same node,
// and maintains immutability by storing decorations separately from IR nodes.
type DecorationRegistry struct {
	// decorations maps NodePath string → DecorationID → DecorationValue
	decorations map[string]map[DecorationID]json.RawMessage
}

// NewDecorationRegistry creates a new empty decoration registry.
func NewDecorationRegistry() DecorationRegistry {
	return DecorationRegistry{
		decorations: make(map[string]map[DecorationID]json.RawMessage),
	}
}

// EmptyDecorationRegistry returns an empty decoration registry.
func EmptyDecorationRegistry() DecorationRegistry {
	return DecorationRegistry{
		decorations: nil,
	}
}

// WithDecoration adds or updates a decoration for a node.
// Returns a new registry instance (maintains immutability).
func (r DecorationRegistry) WithDecoration(nodePath ir.NodePath, decorationID DecorationID, value json.RawMessage) DecorationRegistry {
	newRegistry := DecorationRegistry{
		decorations: make(map[string]map[DecorationID]json.RawMessage),
	}

	// Copy existing decorations
	if r.decorations != nil {
		for nodePathStr, decorations := range r.decorations {
			newDecorations := make(map[DecorationID]json.RawMessage)
			for id, val := range decorations {
				valCopy := make(json.RawMessage, len(val))
				copy(valCopy, val)
				newDecorations[id] = valCopy
			}
			newRegistry.decorations[nodePathStr] = newDecorations
		}
	}

	// Add/update the decoration
	nodePathStr := nodePath.String()
	if newRegistry.decorations[nodePathStr] == nil {
		newRegistry.decorations[nodePathStr] = make(map[DecorationID]json.RawMessage)
	}
	valueCopy := make(json.RawMessage, len(value))
	copy(valueCopy, value)
	newRegistry.decorations[nodePathStr][decorationID] = valueCopy

	return newRegistry
}

// WithoutDecoration removes a decoration for a node.
// Returns a new registry instance (maintains immutability).
func (r DecorationRegistry) WithoutDecoration(nodePath ir.NodePath, decorationID DecorationID) DecorationRegistry {
	if r.decorations == nil {
		return r
	}

	nodePathStr := nodePath.String()
	decorations, exists := r.decorations[nodePathStr]
	if !exists {
		return r
	}

	if _, exists := decorations[decorationID]; !exists {
		return r
	}

	// Create new registry without this decoration
	newRegistry := DecorationRegistry{
		decorations: make(map[string]map[DecorationID]json.RawMessage),
	}

	// Copy all decorations except the one being removed
	for npStr, decs := range r.decorations {
		if npStr == nodePathStr {
			// Copy all decorations for this node except the removed one
			newDecorations := make(map[DecorationID]json.RawMessage)
			for id, val := range decs {
				if id != decorationID {
					valCopy := make(json.RawMessage, len(val))
					copy(valCopy, val)
					newDecorations[id] = valCopy
				}
			}
			if len(newDecorations) > 0 {
				newRegistry.decorations[npStr] = newDecorations
			}
		} else {
			// Copy all decorations for other nodes
			newDecorations := make(map[DecorationID]json.RawMessage)
			for id, val := range decs {
				valCopy := make(json.RawMessage, len(val))
				copy(valCopy, val)
				newDecorations[id] = valCopy
			}
			newRegistry.decorations[npStr] = newDecorations
		}
	}

	return newRegistry
}

// GetDecoration returns the decoration value for a node and decoration ID.
// Returns (value, found).
func (r DecorationRegistry) GetDecoration(nodePath ir.NodePath, decorationID DecorationID) (json.RawMessage, bool) {
	if r.decorations == nil {
		return nil, false
	}

	nodePathStr := nodePath.String()
	decorations, exists := r.decorations[nodePathStr]
	if !exists {
		return nil, false
	}

	value, exists := decorations[decorationID]
	if !exists {
		return nil, false
	}

	// Return defensive copy
	valueCopy := make(json.RawMessage, len(value))
	copy(valueCopy, value)
	return valueCopy, true
}

// GetDecorationsForNode returns all decorations for a node.
// Returns a map of DecorationID → DecorationValue.
func (r DecorationRegistry) GetDecorationsForNode(nodePath ir.NodePath) map[DecorationID]json.RawMessage {
	if r.decorations == nil {
		return nil
	}

	nodePathStr := nodePath.String()
	decorations, exists := r.decorations[nodePathStr]
	if !exists {
		return nil
	}

	// Return defensive copy
	result := make(map[DecorationID]json.RawMessage, len(decorations))
	for id, val := range decorations {
		valCopy := make(json.RawMessage, len(val))
		copy(valCopy, val)
		result[id] = valCopy
	}

	return result
}

// HasDecoration checks if a node has a specific decoration.
func (r DecorationRegistry) HasDecoration(nodePath ir.NodePath, decorationID DecorationID) bool {
	if r.decorations == nil {
		return false
	}

	nodePathStr := nodePath.String()
	decorations, exists := r.decorations[nodePathStr]
	if !exists {
		return false
	}

	_, exists = decorations[decorationID]
	return exists
}

// HasAnyDecoration checks if a node has any decorations.
func (r DecorationRegistry) HasAnyDecoration(nodePath ir.NodePath) bool {
	if r.decorations == nil {
		return false
	}

	nodePathStr := nodePath.String()
	decorations, exists := r.decorations[nodePathStr]
	if !exists {
		return false
	}

	return len(decorations) > 0
}

// AllDecorations returns all decorations in the registry.
// Returns a map of NodePath string → DecorationID → DecorationValue.
func (r DecorationRegistry) AllDecorations() map[string]map[DecorationID]json.RawMessage {
	if r.decorations == nil {
		return nil
	}

	// Return defensive copy
	result := make(map[string]map[DecorationID]json.RawMessage, len(r.decorations))
	for nodePathStr, decorations := range r.decorations {
		newDecorations := make(map[DecorationID]json.RawMessage, len(decorations))
		for id, val := range decorations {
			valCopy := make(json.RawMessage, len(val))
			copy(valCopy, val)
			newDecorations[id] = valCopy
		}
		result[nodePathStr] = newDecorations
	}

	return result
}

// Count returns the total number of decoration entries in the registry.
func (r DecorationRegistry) Count() int {
	if r.decorations == nil {
		return 0
	}

	count := 0
	for _, decorations := range r.decorations {
		count += len(decorations)
	}

	return count
}

// FromDecorationValues creates a DecorationRegistry from a DecorationValues collection
// for a specific decoration ID.
//
// This is useful when loading decoration values from a file and attaching them
// to the registry with a decoration ID.
func FromDecorationValues(decorationID DecorationID, values DecorationValues) DecorationRegistry {
	registry := NewDecorationRegistry()
	allValues := values.All()

	for nodePathStr, value := range allValues {
		nodePath, err := ir.ParseNodePath(nodePathStr)
		if err != nil {
			// Skip invalid node paths
			continue
		}
		registry = registry.WithDecoration(nodePath, decorationID, value)
	}

	return registry
}

// Merge combines multiple decoration registries into one.
// If the same node and decoration ID exist in multiple registries,
// the value from the last registry takes precedence.
func Merge(registries ...DecorationRegistry) DecorationRegistry {
	result := NewDecorationRegistry()

	for _, registry := range registries {
		if registry.decorations == nil {
			continue
		}

		for nodePathStr, decorations := range registry.decorations {
			for decorationID, value := range decorations {
				nodePath, err := ir.ParseNodePath(nodePathStr)
				if err != nil {
					// Skip invalid node paths
					continue
				}
				result = result.WithDecoration(nodePath, decorationID, value)
			}
		}
	}

	return result
}
