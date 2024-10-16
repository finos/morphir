package morphirdirs

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/dirs"
	"github.com/finos/morphir/morphir-go/pkg/morphir/tools"
	"path"
)

type MorphirDirs struct {
	workingDir *dirs.WorkingDir
	configDir  *dirs.ConfigDir
	cacheDir   *dirs.CacheDir
	dataDir    *dirs.DataDir
	homeDir    *dirs.HomeDir
}

func New(options ...func(*MorphirDirs)) *MorphirDirs {
	md := &MorphirDirs{}
	for _, option := range options {
		option(md)
	}
	return md
}

func BasedOn(baseDirs dirs.Dirs) func(dirs *MorphirDirs) {
	return func(mDirs *MorphirDirs) {
		workingDir, ok := baseDirs.WorkingDir()
		if ok {
			mDirs.workingDir = &workingDir
		}
		configDir, ok := baseDirs.ConfigDir()
		if ok {
			dir := path.Join(string(configDir), tools.VendorName, tools.MorphirToolName)
			configDir, ok := dirs.NewConfigDir(dir)
			if ok {
				mDirs.configDir = &configDir
			}
		}

	}
}

func WithWorkingDir(workingDir dirs.WorkingDir) func(md *MorphirDirs) {
	return func(md *MorphirDirs) {
		md.workingDir = &workingDir
	}
}
