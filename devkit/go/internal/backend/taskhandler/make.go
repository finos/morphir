package taskhandler

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/phuslu/log"
)

type MakeHandler struct{}

func (h *MakeHandler) Receive(ctx *actor.Context) {
	switch msg := ctx.Message().(type) {
	case actor.Started:
		log.Info().Objects("message", msg).Msg("MakeHandler started")
	}
}
