package decorations

import (
	"encoding/json"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

// FilterOptions provides options for filtering decorations.
type FilterOptions struct {
	// DecorationIDs filters to only these decoration IDs (if non-empty).
	// If empty, all decorations are included.
	DecorationIDs []decorationmodels.DecorationID
}

// FilterDecorationsForNode filters decorations for a node based on the provided options.
func (a AttachedDistribution) FilterDecorationsForNode(
	nodePath ir.NodePath,
	options FilterOptions,
) map[decorationmodels.DecorationID]json.RawMessage {
	allDecorations := a.GetDecorationsForNode(nodePath)
	if allDecorations == nil {
		return nil
	}

	// If no filter specified, return all
	if len(options.DecorationIDs) == 0 {
		return allDecorations
	}

	// Build a set of allowed IDs for efficient lookup
	allowedIDs := make(map[decorationmodels.DecorationID]bool, len(options.DecorationIDs))
	for _, id := range options.DecorationIDs {
		allowedIDs[id] = true
	}

	// Filter decorations
	filtered := make(map[decorationmodels.DecorationID]json.RawMessage)
	for id, value := range allDecorations {
		if allowedIDs[id] {
			// Return defensive copy
			valueCopy := make(json.RawMessage, len(value))
			copy(valueCopy, value)
			filtered[id] = valueCopy
		}
	}

	return filtered
}

// GetAllNodesWithDecorations returns all NodePaths that have at least one decoration.
func (a AttachedDistribution) GetAllNodesWithDecorations() []ir.NodePath {
	allDecorations := a.Registry().AllDecorations()
	if allDecorations == nil {
		return nil
	}

	nodePaths := make([]ir.NodePath, 0, len(allDecorations))
	for nodePathStr := range allDecorations {
		nodePath, err := ir.ParseNodePath(nodePathStr)
		if err != nil {
			// Skip invalid node paths
			continue
		}
		nodePaths = append(nodePaths, nodePath)
	}

	return nodePaths
}

// GetAllNodesWithDecoration returns all NodePaths that have a specific decoration ID.
func (a AttachedDistribution) GetAllNodesWithDecoration(decorationID decorationmodels.DecorationID) []ir.NodePath {
	allDecorations := a.Registry().AllDecorations()
	if allDecorations == nil {
		return nil
	}

	nodePaths := make([]ir.NodePath, 0)
	for nodePathStr, decorations := range allDecorations {
		if _, hasDecoration := decorations[decorationID]; hasDecoration {
			nodePath, err := ir.ParseNodePath(nodePathStr)
			if err != nil {
				// Skip invalid node paths
				continue
			}
			nodePaths = append(nodePaths, nodePath)
		}
	}

	return nodePaths
}

// CountDecorations returns the total number of decoration entries.
func (a AttachedDistribution) CountDecorations() int {
	return a.Registry().Count()
}

// CountDecorationsForNode returns the number of decorations for a specific node.
func (a AttachedDistribution) CountDecorationsForNode(nodePath ir.NodePath) int {
	decorations := a.GetDecorationsForNode(nodePath)
	if decorations == nil {
		return 0
	}
	return len(decorations)
}

// ListDecorationIDs returns all decoration IDs that exist in the registry.
func (a AttachedDistribution) ListDecorationIDs() []decorationmodels.DecorationID {
	allDecorations := a.Registry().AllDecorations()
	if allDecorations == nil {
		return nil
	}

	// Build a set of unique decoration IDs
	idSet := make(map[decorationmodels.DecorationID]bool)
	for _, decorations := range allDecorations {
		for id := range decorations {
			idSet[id] = true
		}
	}

	// Convert to slice
	ids := make([]decorationmodels.DecorationID, 0, len(idSet))
	for id := range idSet {
		ids = append(ids, id)
	}

	return ids
}

// GetDecorationsByID returns all decorations of a specific type across all nodes.
//
// Returns a map of NodePath string → DecorationValue.
func (a AttachedDistribution) GetDecorationsByID(decorationID decorationmodels.DecorationID) map[string]json.RawMessage {
	allDecorations := a.Registry().AllDecorations()
	if allDecorations == nil {
		return nil
	}

	result := make(map[string]json.RawMessage)
	for nodePathStr, decorations := range allDecorations {
		if value, hasDecoration := decorations[decorationID]; hasDecoration {
			// Return defensive copy
			valueCopy := make(json.RawMessage, len(value))
			copy(valueCopy, value)
			result[nodePathStr] = valueCopy
		}
	}

	return result
}
