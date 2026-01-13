package decorations

import (
	"encoding/json"
	"fmt"

	"github.com/finos/morphir/pkg/config"
	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

// AttachedDistribution represents a Distribution with attached decorations.
//
// This maintains immutability by keeping decorations separate from the IR.
// The distribution itself is not modified.
type AttachedDistribution struct {
	distribution ir.Distribution
	registry     decorationmodels.DecorationRegistry
}

// Distribution returns the underlying Morphir IR distribution.
func (a AttachedDistribution) Distribution() ir.Distribution {
	return a.distribution
}

// Registry returns the decoration registry.
func (a AttachedDistribution) Registry() decorationmodels.DecorationRegistry {
	return a.registry
}

// NewAttachedDistribution creates an AttachedDistribution from a distribution and registry.
func NewAttachedDistribution(distribution ir.Distribution, registry decorationmodels.DecorationRegistry) AttachedDistribution {
	return AttachedDistribution{
		distribution: distribution,
		registry:     registry,
	}
}

// WithRegistry returns a new AttachedDistribution with an updated registry.
func (a AttachedDistribution) WithRegistry(registry decorationmodels.DecorationRegistry) AttachedDistribution {
	return AttachedDistribution{
		distribution: a.distribution,
		registry:     registry,
	}
}

// LoadAndAttachDecorations loads decoration values from files and attaches them to a distribution.
//
// This function:
//   - Loads decoration configurations from the project config
//   - Loads decoration values from storage files
//   - Validates decoration values against their schemas (if validate is true)
//   - Creates a DecorationRegistry and attaches it to the distribution
//
// Returns an AttachedDistribution with all decorations loaded and validated.
func LoadAndAttachDecorations(
	distribution ir.Distribution,
	projectConfig config.ProjectSection,
	validate bool,
) (AttachedDistribution, error) {
	registry := decorationmodels.EmptyDecorationRegistry()
	decorations := projectConfig.Decorations()

	if len(decorations) == 0 {
		// No decorations configured - return distribution with empty registry
		return NewAttachedDistribution(distribution, registry), nil
	}

	// Load each decoration
	for decorationID, decorationConfig := range decorations {
		decID := decorationmodels.DecorationID(decorationID)

		// Load decoration values from file
		values, err := LoadDecorationValues(decorationConfig.StorageLocation())
		if err != nil {
			return AttachedDistribution{}, fmt.Errorf("load decoration %q values: %w", decorationID, err)
		}

		// Validate if requested
		if validate {
			// Load decoration IR
			decIR, err := LoadDecorationIR(decorationConfig.IR())
			if err != nil {
				return AttachedDistribution{}, fmt.Errorf("load decoration %q IR: %w", decorationID, err)
			}

			// Validate all values
			result := ValidateDecorationValues(decIR, decorationConfig.EntryPoint(), values)
			if !result.Valid {
				return AttachedDistribution{}, fmt.Errorf("decoration %q validation failed: %d errors", decorationID, len(result.Errors))
			}
		}

		// Attach decorations to registry
		decRegistry := decorationmodels.FromDecorationValues(decID, values)
		registry = decorationmodels.Merge(registry, decRegistry)
	}

	return NewAttachedDistribution(distribution, registry), nil
}

// GetDecorationForNode retrieves a decoration value for a specific node and decoration ID.
//
// This is a convenience function that queries the registry.
func (a AttachedDistribution) GetDecorationForNode(nodePath ir.NodePath, decorationID decorationmodels.DecorationID) (json.RawMessage, bool) {
	return a.registry.GetDecoration(nodePath, decorationID)
}

// GetDecorationsForNode retrieves all decorations for a specific node.
func (a AttachedDistribution) GetDecorationsForNode(nodePath ir.NodePath) map[decorationmodels.DecorationID]json.RawMessage {
	return a.registry.GetDecorationsForNode(nodePath)
}

// HasDecoration checks if a node has a specific decoration.
func (a AttachedDistribution) HasDecoration(nodePath ir.NodePath, decorationID decorationmodels.DecorationID) bool {
	return a.registry.HasDecoration(nodePath, decorationID)
}

// HasAnyDecoration checks if a node has any decorations.
func (a AttachedDistribution) HasAnyDecoration(nodePath ir.NodePath) bool {
	return a.registry.HasAnyDecoration(nodePath)
}
