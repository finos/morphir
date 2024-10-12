package morphir

import (
	"github.com/finos/morphir/morphir-go/internal/config"
)

type AppHost interface {
	ConfigMgr() ConfigMgr
}

type ConfigMgr = config.ConfigMgr

func NewConfigMgr() *ConfigMgr {
	return config.DefaultConfigMgr{}
}
