package host

import (
	"github.com/finos/morphir/integrations/go/pkg/morphir/info"
)

type Kind int

const (
	Morphir Kind = iota
	Emerald
)

func (k Kind) ToolName() string {
	if k == Emerald {
		return info.EmeraldToolName
	}
	return info.MorphirToolName
}
