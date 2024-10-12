package config

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir"
	gap "github.com/muesli/go-app-paths"
)

var (
	/// Prioritized list of Morphir workspace/project config file names
	ProjectFileNames        = []string{"morphir.yml", "morphir.yaml", "morphir.json"}
	MorphirToolingFileNames = []string{"morphir-tooling.yml"}
)

type ConfigMgr interface {
	AppConfigPaths() []string
}

type DefaultConfigMgr struct {
	appConfigPaths []string
}

func NewDefaultConfigMgr() *DefaultConfigMgr {
	scope := gap.NewVendorScope(gap.User, morphir.VendorName, morphir.AppName)
	return &DefaultConfigMgr{appConfigPaths: appConfigPaths}
}

func (mgr *DefaultConfigMgr) AppConfigPaths() []string {
	return mgr.appConfigPaths
}

func defaultAppConfigPaths(scope gap.Scope) []string {

	return paths
}
