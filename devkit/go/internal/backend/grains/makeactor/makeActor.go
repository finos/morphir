package makeactor

import (
	"github.com/asynkron/protoactor-go/actor"
	"log/slog"
)

type MakeCommand struct {
	project string
}

type MakeActor struct{}

func (m *MakeActor) Receive(context actor.Context) {
	switch msg := context.Message().(type) {
	case *MakeCommand:
		context.Logger().Info("Received MakeCommand", slog.String("msg", "MakeCommand"))
	default:
		context.Logger().Info("Received unknown message", msg)
	}
}

func Props() *actor.Props {
	return actor.PropsFromProducer(func() actor.Actor {
		return &MakeActor{}
	})
}
