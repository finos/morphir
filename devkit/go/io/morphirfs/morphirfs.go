package morphirfs

import (
	"github.com/phuslu/log"
	goOS "os"

	"github.com/finos/morphir/devkit/go/tool"
	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
)

type MorphirFS interface {
	hackpadfs.FS
	hackpadfs.LstatFS
	hackpadfs.StatFS
}

type WorkingDirFS interface {
	FS
	WorkingDir() (tool.WorkingDir, error)
}

type FS struct {
	rootFS     MorphirFS
	workingDir tool.WorkingDir
}

func New(options ...func(*FS)) *FS {
	fs := defaultFS()

	for _, option := range options {
		option(fs)
	}

	return fs
}

func (fs *FS) Open(name string) (hackpadfs.File, error) {
	return fs.rootFS.Open(name)
}

func (fs *FS) Lstat(name string) (hackpadfs.FileInfo, error) {
	log.Info().Msg("Lstat called for: " + name)
	return fs.rootFS.Lstat(name)
}

func (fs *FS) Stat(name string) (hackpadfs.FileInfo, error) {
	log.Info().Msg("Stat called for: " + name)
	res, err := fs.rootFS.Stat(name)
	if err != nil {
		log.Error().Err(err).Msg("Error occurred during Stat")
	} else {
		log.Info().Msg("Stat successful for: " + name)
	}
	return res, err
}

func (fs *FS) WorkingDir() (tool.WorkingDir, error) {
	return fs.workingDir, nil
}

func (fs *FS) AsHackpadFS() hackpadfs.FS {
	return fs
}

func DefaultMorphirFS() MorphirFS {
	fs := os.NewFS()
	return fs
}

func defaultFS() *FS {
	workingDir, err := goOS.Getwd()
	if err != nil {
		workingDir = "."
	}
	return &FS{
		rootFS:     DefaultMorphirFS(),
		workingDir: tool.WorkingDir(workingDir),
	}
}
