package config

import (
	"errors"
	"github.com/finos/morphir/morphir-go/pkg/morphir/info"
	gap "github.com/muesli/go-app-paths"
)

type Scope struct {
	scope gap.Scope
}

func NewScope(options ...func(*Scope)) *Scope {
	scope := NewUserScope()
	for _, option := range options {
		option(scope)
	}

	return scope
}

func NewUserScope() *Scope {
	gs := gap.NewVendorScope(gap.User, info.VendorName, info.MorphirToolName)
	return &Scope{
		scope: *gs,
	}
}

func ScopeWithAppName(name string) func(*Scope) {
	return func(scope *Scope) {
		gs := gap.NewVendorScope(gap.User, info.VendorName, name)
		scope.scope = *gs
	}
}

func (s *Scope) IsSystem() bool {
	switch s.scope.Type {
	case gap.System:
		return true
	default:
		return false
	}
}

func (s *Scope) IsUser() bool {
	switch s.scope.Type {
	case gap.User:
		return true
	default:
		return false
	}
}

func (s *Scope) IsCustomHome() bool {
	switch s.scope.Type {
	case gap.CustomHome:
		return true
	default:
		return false
	}
}

// ConfigDirs returns a priority-sorted slice of all the application's config dirs.
func (s *Scope) ConfigDirs() ([]string, error) {
	return s.scope.ConfigDirs()
}

func (s *Scope) ConfigDir() (string, error) {
	dirs, err := s.ConfigDirs()
	if err != nil {
		return "", err
	}
	if len(dirs) < 1 {
		return "", errors.New("no config directory found")
	}
	return dirs[0], nil

}
