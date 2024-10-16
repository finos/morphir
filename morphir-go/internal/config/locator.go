package config

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/tools"
	gap "github.com/muesli/go-app-paths"
)

var (
	defaultConfigScope = gap.NewVendorScope(gap.User, tools.VendorName, tools.MorphirToolName)
)

func DefaultConfigScope() ConfigScope {
	return ConfigScope{scope: *defaultConfigScope}
}

type ConfigScope struct {
	scope gap.Scope
}

type Locator interface{}

type ToolingConfigLocator interface {
}
