package decorations

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// DecorationIR represents a loaded decoration schema IR.
// It contains the distribution and provides methods to validate entry points
// and extract type definitions.
//
// This is a domain model type - the actual loading logic is in pkg/tooling/decorations.
type DecorationIR struct {
	distribution ir.Distribution
	irPath       string
}

// Distribution returns the Morphir IR distribution for this decoration schema.
func (d DecorationIR) Distribution() ir.Distribution {
	return d.distribution
}

// IRPath returns the path to the decoration IR file.
func (d DecorationIR) IRPath() string {
	return d.irPath
}

// NewDecorationIR creates a new DecorationIR from a distribution and file path.
// This is typically called by the loading logic in pkg/tooling/decorations.
func NewDecorationIR(distribution ir.Distribution, irPath string) DecorationIR {
	return DecorationIR{
		distribution: distribution,
		irPath:       irPath,
	}
}
