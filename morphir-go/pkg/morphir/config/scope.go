package config

import (
	gap "github.com/muesli/go-app-paths"
)

type Scope struct {
	scope gap.Scope
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
