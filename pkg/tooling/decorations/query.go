package decorations

import (
	"encoding/json"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

// GetDecorationForType retrieves a decoration value for a type node.
//
// The type is identified by its FQName: PackageName:ModuleName:TypeName
func (a AttachedDistribution) GetDecorationForType(
	typeFQName ir.FQName,
	decorationID decorationmodels.DecorationID,
) (json.RawMessage, bool) {
	nodePath := ir.NodePathFromFQName(typeFQName)
	return a.GetDecorationForNode(nodePath, decorationID)
}

// GetDecorationsForType retrieves all decorations for a type node.
func (a AttachedDistribution) GetDecorationsForType(typeFQName ir.FQName) map[decorationmodels.DecorationID]json.RawMessage {
	nodePath := ir.NodePathFromFQName(typeFQName)
	return a.GetDecorationsForNode(nodePath)
}

// GetDecorationForValue retrieves a decoration value for a value node.
//
// The value is identified by its FQName: PackageName:ModuleName:ValueName
func (a AttachedDistribution) GetDecorationForValue(
	valueFQName ir.FQName,
	decorationID decorationmodels.DecorationID,
) (json.RawMessage, bool) {
	nodePath := ir.NodePathFromFQName(valueFQName)
	return a.GetDecorationForNode(nodePath, decorationID)
}

// GetDecorationsForValue retrieves all decorations for a value node.
func (a AttachedDistribution) GetDecorationsForValue(valueFQName ir.FQName) map[decorationmodels.DecorationID]json.RawMessage {
	nodePath := ir.NodePathFromFQName(valueFQName)
	return a.GetDecorationsForNode(nodePath)
}

// GetDecorationForModule retrieves a decoration value for a module node.
//
// The module is identified by its QualifiedModuleName: PackageName:ModuleName
func (a AttachedDistribution) GetDecorationForModule(
	moduleQName ir.QualifiedModuleName,
	decorationID decorationmodels.DecorationID,
) (json.RawMessage, bool) {
	nodePath := ir.NodePathFromQualifiedModuleName(moduleQName)
	return a.GetDecorationForNode(nodePath, decorationID)
}

// GetDecorationsForModule retrieves all decorations for a module node.
func (a AttachedDistribution) GetDecorationsForModule(moduleQName ir.QualifiedModuleName) map[decorationmodels.DecorationID]json.RawMessage {
	nodePath := ir.NodePathFromQualifiedModuleName(moduleQName)
	return a.GetDecorationsForNode(nodePath)
}

// HasDecorationForType checks if a type node has a specific decoration.
func (a AttachedDistribution) HasDecorationForType(typeFQName ir.FQName, decorationID decorationmodels.DecorationID) bool {
	nodePath := ir.NodePathFromFQName(typeFQName)
	return a.HasDecoration(nodePath, decorationID)
}

// HasDecorationForValue checks if a value node has a specific decoration.
func (a AttachedDistribution) HasDecorationForValue(valueFQName ir.FQName, decorationID decorationmodels.DecorationID) bool {
	nodePath := ir.NodePathFromFQName(valueFQName)
	return a.HasDecoration(nodePath, decorationID)
}

// HasDecorationForModule checks if a module node has a specific decoration.
func (a AttachedDistribution) HasDecorationForModule(moduleQName ir.QualifiedModuleName, decorationID decorationmodels.DecorationID) bool {
	nodePath := ir.NodePathFromQualifiedModuleName(moduleQName)
	return a.HasDecoration(nodePath, decorationID)
}

// HasAnyDecorationForType checks if a type node has any decorations.
func (a AttachedDistribution) HasAnyDecorationForType(typeFQName ir.FQName) bool {
	nodePath := ir.NodePathFromFQName(typeFQName)
	return a.HasAnyDecoration(nodePath)
}

// HasAnyDecorationForValue checks if a value node has any decorations.
func (a AttachedDistribution) HasAnyDecorationForValue(valueFQName ir.FQName) bool {
	nodePath := ir.NodePathFromFQName(valueFQName)
	return a.HasAnyDecoration(nodePath)
}

// HasAnyDecorationForModule checks if a module node has any decorations.
func (a AttachedDistribution) HasAnyDecorationForModule(moduleQName ir.QualifiedModuleName) bool {
	nodePath := ir.NodePathFromQualifiedModuleName(moduleQName)
	return a.HasAnyDecoration(nodePath)
}
