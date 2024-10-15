package config

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/configmode"
	"github.com/hack-pad/hackpadfs"
)

var (
	/// Prioritized list of Morphir workspace/project config file names
	ProjectFileNames              = []string{"morphir.yml", "morphir.yaml", "morphir.json"}
	MorphirToolingConfigFileNames = []string{"morphir-tooling.yml"}
)

type ToolingConfigMgr interface {
	// ToolingConfigPaths returns the list of paths to search for Morphir tooling configuration files
	ToolingConfigPaths(path string, scope ConfigScope, mode configmode.ConfigMode) []string
}

type ConfigMgr interface {
	ToolingConfigMgr
	//AppConfigPaths() []string
}

type DefaultConfigMgr struct {
	//appConfigPaths []string
}

func NewDefaultConfigMgr() *DefaultConfigMgr {
	//scope := DefaultConfigScope()
	//return &DefaultConfigMgr{appConfigPaths: appConfigPaths}
	return &DefaultConfigMgr{}
}

func (mgr *DefaultConfigMgr) ToolingConfigPaths(path string, mode configmode.ConfigMode) []string {
	scope := DefaultConfigScope()
	var paths []string
	mode = mode.Canonicalize()
	if mode.HasLocal() {
		// TODO: Ensure path is a directory
		hackpadfs.d
	}

	return nil
}

//func (mgr *DefaultConfigMgr) AppConfigPaths() []string {
//	return mgr.appConfigPaths
//}
//
//func defaultAppConfigPaths(scope gap.Scope) []string {
//
//	return paths
//}
