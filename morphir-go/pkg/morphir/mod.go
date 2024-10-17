package morphir

import (
	"github.com/finos/morphir/morphir-go/internal/config"
	"github.com/finos/morphir/morphir-go/pkg/morphir/host"
)

type ConfigMgr = config.ConfigMgr
type Host = host.Host

func NewHost(options ...func(*Host)) *Host {
	return host.New(options...)
}
