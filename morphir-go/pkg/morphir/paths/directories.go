package paths

type WorkingDir string

type ConfigDir string

type CacheDir string

type DataDir string

type HomeDir string

type WorkspaceDir string

type ProjectDir string

type WorkingDirProvider interface {
	WorkingDir() (dir WorkingDir, err error)
}

type ConfigDirProvider interface {
	ConfigDir() (dir ConfigDir, err error)
}

type CacheDirProvider interface {
	CacheDir() (dir CacheDir, err error)
}

type DataDirProvider interface {
	DataDir() (dir DataDir, err error)
}

type HomeDirProvider interface {
	HomeDir() (dir HomeDir, err error)
}

type WorkspaceDirProvider interface {
	WorkspaceDir() (dir WorkspaceDir, err error)
}

type BaseDirs interface {
	WorkingDirProvider
	ConfigDirProvider
	CacheDirProvider
	DataDirProvider
	HomeDirProvider
}

type Dirs interface {
	WorkingDirProvider
	ConfigDirProvider
	CacheDirProvider
	DataDirProvider
	HomeDirProvider
	WorkspaceDirProvider
}
