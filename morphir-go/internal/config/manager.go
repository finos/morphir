package config

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/configmode"
)

var (
	/// Prioritized list of Morphir workspace/project config file names
	ProjectFileNames        = []string{"morphir.yml", "morphir.yaml", "morphir.json"}
	MorphirToolingFileNames = []string{"morphir-tooling.yml"}
)

type ToolingConfigMgr interface {
	ToolingConfigPaths(scope ConfigScope, mode configmode.ConfigMode) []string
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

func (mgr *DefaultConfigMgr) ToolingConfigPaths(mode configmode.ConfigMode) []string {
	//scope := DefaultConfigScope()
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
