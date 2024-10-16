package hostdirs

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/config"
	"github.com/finos/morphir/morphir-go/pkg/morphir/dirs"
)

type HostDirs struct {
	workingDir *dirs.WorkingDir
	configDir  *dirs.ConfigDir
	cacheDir   *dirs.CacheDir
	dataDir    *dirs.DataDir
	homeDir    *dirs.HomeDir
}

func New(scope config.Scope, options ...func(*HostDirs)) *HostDirs {
	h := &HostDirs{}
	for _, option := range options {
		option(h)
	}
	return h
}
