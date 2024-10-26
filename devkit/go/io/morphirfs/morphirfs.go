package morphirfs

import (
	goOS "os"
	"strings"

	"github.com/finos/morphir/devkit/go/tool"
	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
)

type baseFS interface {
	hackpadfs.FS
	hackpadfs.LstatFS
	hackpadfs.StatFS
}

type WorkingDirFS interface {
	hackpadfs.FS
	WorkingDir() (tool.WorkingDir, error)
}

type FS struct {
	baseFS
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

func CanonicalizePath(path string) string {
	if !hackpadfs.ValidPath(path) && strings.HasPrefix(path, "/") {
		return path[1:]
	}
	return path
}

func defaultFS() (*FS, error) {
	workingDir, err := goOS.Getwd()
	if err != nil {
		return nil, err
	}

	fs := os.NewFS()
	return &FS{
		baseFS:     fs,
		workingDir: tool.WorkingDir(workingDir),
	}, nil
}
