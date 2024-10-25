package morphirfs

import (
	goOS "os"

	"github.com/finos/morphir/devkit/go/tool"
	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
)

var _ interface {
	hackpadfs.FS
	hackpadfs.LstatFS
	hackpadfs.StatFS
} = &FS{}

type WorkingDirFS interface {
	FS
	WorkingDir() (tool.WorkingDir, error)
}

type FS struct {
	os.FS
	workingDir tool.WorkingDir
}

func New(options ...func(*FS)) (*FS, error) {
	fs, err := defaultFS()
	if err != nil {
		return nil, err
	}

	for _, option := range options {
		option(fs)
	}

	return fs, nil
}

func (fs *FS) WorkingDir() (tool.WorkingDir, error) {
	return fs.workingDir, nil
}

func (fs *FS) AsHackpadFS() hackpadfs.FS {
	return fs
}

func defaultFS() (*FS, error) {
	workingDir, err := goOS.Getwd()
	if err != nil {
		return nil, err
	}

	fs := os.NewFS()
	return &FS{
		FS:         *fs,
		workingDir: tool.WorkingDir(workingDir),
	}, nil
}
