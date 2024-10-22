package inprocess

import (
	"github.com/asynkron/protoactor-go/actor"
	"github.com/phuslu/log"
)

type Session struct {
	system *actor.ActorSystem
}

func New() *Session {
	sys := actor.NewActorSystem()
	return &Session{
		system: sys,
	}
}

func (s *Session) Start() {
	log.Info().Msg("Starting in-process session...")
	log.Info().Msg("In-process session started")
}

func (s *Session) Close() {
	log.Info().Msg("Closing in-process session...")
	s.system.Shutdown()
	log.Info().Msg("In-process session closed")
}
