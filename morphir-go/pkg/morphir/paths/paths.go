package paths

import "github.com/finos/morphir/morphir-go/pkg/morphir/config"

type Paths struct {
	configScope  config.Scope
	workingDir   *WorkingDir
	configDir    *ConfigDir
	cacheDir     *CacheDir
	dataDir      *DataDir
	homeDir      *HomeDir
	workspaceDir *WorkspaceDir
}

func New(options ...func(*Paths)) *Paths {
	p := &Paths{}
	for _, option := range options {
		option(p)
	}
	return p
}

func (paths *Paths) SetWorkingDir(workingDir *WorkingDir) (*Paths, error) {
	//TODO: add verifications
	paths.workingDir = workingDir
	return paths, nil
}

func WithConfigScope(scope config.Scope) func(paths *Paths) {
	return func(mDirs *Paths) {
		//workingDir, ok := provider.WorkingDir()
		//if ok {
		//	mDirs.workingDir = &workingDir
		//}
		//configDir, ok := baseDirs.ConfigDir()
		//if ok {
		//	dir := path.Join(string(configDir), tools.VendorName, tools.MorphirToolName)
		//	configDir, ok := paths.NewConfigDir(dir)
		//	if ok {
		//		mDirs.configDir = &configDir
		//	}
		//}
	}
}

func NewConfigDir(path string) (dir ConfigDir, ok bool) {
	//TODO: Perform checks to ensure validity of the path
	return dir, true
}
