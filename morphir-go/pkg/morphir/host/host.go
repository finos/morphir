package host

import (
	"github.com/finos/morphir/morphir-go/pkg/morphir/config"
	"github.com/finos/morphir/morphir-go/pkg/morphir/paths"

	"github.com/hack-pad/hackpadfs"
	"github.com/hack-pad/hackpadfs/os"
)

type Host struct {
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
	return host
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
	return WithFS(os.NewFS())
}

func WithPaths(paths paths.Paths) func(*Host) {
	return func(host *Host) {
		host.paths = &paths
	}
}
