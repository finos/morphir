package host

import (
	goOS "os"

	"github.com/finos/morphir/morphir-go/pkg/morphir/config"
	"github.com/finos/morphir/morphir-go/pkg/morphir/paths"
	"github.com/hack-pad/hackpadfs/os"

	"github.com/hack-pad/hackpadfs"
)

type Host struct {
	kind       Kind
	configMode config.Mode
	fs         hackpadfs.FS
	paths      *paths.Paths
}

func New(options ...func(*Host)) *Host {
	host := &Host{
		configMode: config.NewMode(),
		paths:      paths.New(),
	}
	for _, option := range options {
		option(host)
	}

	// If the user hasn't provided a filesystem, use the default OS filesystem
	if host.fs == nil {
		WithOsFS()(host)
	}
	return setup(host)
}

func (h *Host) Kind() Kind {
	return h.kind
}

func WithWorkingDir(dir paths.WorkingDir) func(*Host) {
	return func(h *Host) {
		_, _ = h.paths.SetWorkingDir(&dir)
	}
}

func WithKind(kind Kind) func(*Host) {
	return func(h *Host) {
		h.kind = kind
	}
}

func WithConfigMode(mode config.Mode) func(*Host) {
	return func(host *Host) {
		host.configMode = mode
	}
}

func WithFS(fs hackpadfs.FS) func(*Host) {
	return func(host *Host) {
		host.fs = fs
	}
}

func WithOsFS() func(*Host) {
	return func(host *Host) {
		WithFS(os.NewFS())(host)
		workingDir, err := goOS.Getwd()
		if err == nil {
			WithWorkingDir(paths.WorkingDir(workingDir))(host)
		}
	}
}

func WithPaths(paths paths.Paths) func(*Host) {
	return func(host *Host) {
		host.paths = &paths
	}
}

func setup(host *Host) *Host {
	if host.fs == nil {
		WithOsFS()(host)
	}
	if host.paths == nil {
		host.paths = paths.New()
	}

	return host
}
