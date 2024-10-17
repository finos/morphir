package paths

type WorkingDir string

type ConfigDir string

type CacheDir string

type DataDir string

type HomeDir string

type WorkspaceDir string

type ProjectDir string

type WorkingDirProvider interface {
	WorkingDir() (dir WorkingDir, ok bool)
}

type ConfigDirProvider interface {
	ConfigDir() (dir ConfigDir, ok bool)
}

type CacheDirProvider interface {
	CacheDir() (dir CacheDir, ok bool)
}

type DataDirProvider interface {
	DataDir() (dir DataDir, ok bool)
}

type HomeDirProvider interface {
	HomeDir() (dir HomeDir, ok bool)
}

type WorkspaceDirProvider interface {
	WorkspaceDir() (dir WorkspaceDir, ok bool)
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
