package inprocess

import (
	"github.com/asynkron/protoactor-go/actor"
	"github.com/finos/morphir/devkit/go/internal/backend/grains/makeactor"
	"github.com/phuslu/log"
)

type Session struct {
	system  *actor.ActorSystem
	makePid *actor.PID
}

func New() *Session {
	sys := actor.NewActorSystem()

	props := makeactor.Props()
	makePid := sys.Root.Spawn(props)

	return &Session{
		system:  sys,
		makePid: makePid,
	}
}

func (s *Session) System() *actor.ActorSystem {
	return s.system
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
