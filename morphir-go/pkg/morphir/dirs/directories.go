package dirs

type WorkingDir string

type ConfigDir string

type CacheDir string

type DataDir string

type HomeDir string

type WorkspaceDir string

type ProjectDir string

type Dirs interface {
	WorkingDir() (dir WorkingDir, ok bool)
	ConfigDir() (dir ConfigDir, ok bool)
	CacheDir() (dir CacheDir, ok bool)
	DataDir() (dir, ok bool)
	HomeDir() (dir HomeDir, ok bool)
}

func NewConfigDir(path string) (dir ConfigDir, ok bool) {
	//TODO: Perform checks to ensure validity of the path
	return dir, true
}
