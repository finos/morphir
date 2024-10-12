package morphir

import (
	"github.com/finos/morphir/morphir-go/internal/config"
)

const (
	// AppName is the name of the application
	AppName = "morphir"

	// VendorName is the name of the vendor
	VendorName = "finos"
)

type AppHost interface {
	ConfigMgr() ConfigMgr
}

type ConfigMgr = config.ConfigMgr

func NewConfigMgr() *ConfigMgr {
	return config.DefaultConfigMgr{}
}
