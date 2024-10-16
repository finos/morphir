package host

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/dirs"
	"github.com/finos/morphir/morphir-go/pkg/morphir/host/hostdirs"

	goOS "os"

	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
)

type Host struct {
	fs   hackpadfs.FS
	dirs hostdirs.HostDirs
}

func New(options ...func(*Host)) *Host {
	host := &Host{dirs: dirs.Dirs{}}
	for _, option := range options {
		option(host)
	}

	// If the user hasn't provided a filesystem, use the default OS filesystem
	if host.fs == nil {
		host.fs = os.NewFS()
	}
	return host
}

func (host *Host) WithFS(fs hackpadfs.FS) func(*Host) {
	return func(appHost *Host) {
		appHost.fs = fs
	}
}

func WithWorkingDir(workingDir string) func(*Host) {
	return func(host *Host) {
		host.dirs.workingDir = hostdirs.WorkingDir(workingDir)
	}
}

func WithOsWorkingDir() func(*Host) {
	return func(appHost *Host) {
		workingDirectory, err := goOS.Getwd()
		if err != nil {
			panic(err)
		}
		appHost.workingDir = workingDirectory
	}
}
