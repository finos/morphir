package config

import (
	"github.com/finos/morphir/morphir-go/internal/app"
	gap "github.com/muesli/go-app-paths"
)

var (
	defaultConfigScope = gap.NewVendorScope(gap.User, app.VendorName, app.AppName)
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
