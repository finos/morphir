package paths

import (
	"github.com/bmatcuk/doublestar/v4"
	"github.com/finos/morphir/integrations/go/pkg/morphir/config"
)

type Paths struct {
	configScope  *config.Scope
	workingDir   *WorkingDir
	configDir    *ConfigDir
	cacheDir     *CacheDir
	dataDir      *DataDir
	homeDir      *HomeDir
	workspaceDir *WorkspaceDir
}

func Match(pattern string, name string) (bool, error) {
	return doublestar.Match(pattern, name)
}

func New(options ...func(*Paths)) *Paths {
	p := &Paths{}
	for _, option := range options {
		option(p)
	}

	if p.configScope == nil {
		WithConfigScope(config.NewScope())(p)
	}
	return p
}

func (paths *Paths) IsConfigDirSet() bool {
	return paths != nil && paths.configDir != nil
}

func (paths *Paths) ConfigDir() (ConfigDir, bool) {
	if paths == nil || paths.configDir == nil {
		return "", false
	}
	return *paths.configDir, true
}

func (paths *Paths) IsWorkingDirSet() bool {
	return paths != nil && paths.workingDir != nil
}

func (paths *Paths) WorkingDir() (WorkingDir, bool) {
	if paths.workingDir == nil {
		return "", false
	}
	return *paths.workingDir, true
}

func (paths *Paths) SetWorkingDir(workingDir *WorkingDir) (*Paths, error) {
	//TODO: add verifications
	paths.workingDir = workingDir
	return paths, nil
}

func WithConfigScope(scope *config.Scope) func(*Paths) {
	return func(paths *Paths) {
		paths.configScope = scope
		//workingDir, ok := paths.WorkingDir()
		//if ok {
		//	//TODO: Apply any path changes which may happen as a result of the new scope
		//	paths.workingDir = workingDir
		//}
		configDir, ok := paths.ConfigDir()
		if !ok {

		}
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
