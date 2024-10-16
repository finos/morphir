package config

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/config/configmode"
	"github.com/hack-pad/hackpadfs"
)

var (
	/// Prioritized list of Morphir workspace/project config file names
	ProjectFileNames              = []string{"morphir.yml", "morphir.yaml", "morphir.json"}
	MorphirToolingConfigFileNames = []string{"morphir-tooling.yml"}
)

type ToolingConfigFS interface {
	FsRoots() []hackpadfs.FS
}

type ToolingConfigMgr interface {
	// ToolingConfigPaths returns the list of paths to search for Morphir tooling configuration files
	ToolingConfigPaths(fs hackpadfs.StatFS, path string, scope ConfigScope, mode configmode.ConfigMode) []string
}

type ConfigMgr interface {
	ToolingConfigMgr
	//AppConfigPaths() []string
}

type DefaultConfigMgr struct {
	//fsRoots []hackpadfs.FS
	//appConfigPaths []string
}

// func NewDefaultOsConfigMgr() *DefaultConfigMgr {
// 	//scope := DefaultConfigScope()
// 	//return &DefaultConfigMgr{appConfigPaths: appConfigPaths}
// 	fs := os.NewFS()
// 	sub := fs.Sub("morphir")
// 	return &DefaultConfigMgr{FS: fs}
// }

// func (mgr *DefaultConfigMgr) ToolingConfigPaths(path string, mode configmode.ConfigMode) []string {
// 	scope := DefaultConfigScope()
// 	var paths []string
// 	mode = mode.Canonicalize()
// 	if mode.HasLocal() {
// 		// TODO: Ensure path is a directory
// 		hackpadfs.d
// 	}

// 	return nil
// }

//func (mgr *DefaultConfigMgr) AppConfigPaths() []string {
//	return mgr.appConfigPaths
//}
//
//func defaultAppConfigPaths(scope gap.Scope) []string {
//
//	return paths
//}
