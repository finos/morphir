package broker

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/phuslu/log"
)

type Start struct {
}

type brokerActor struct {
	inProcess bool
}

func NewBroker(config Config) actor.Producer {
	return func() actor.Receiver {
		return &brokerActor{
			inProcess: config.InProcess,
		}
	}
}

func (b *brokerActor) Receive(ctx *actor.Context) {
	switch msg := ctx.Message().(type) {
	case actor.Initialized:
		log.Info().Msg("BrokerActor initialized")
	default:

		if msg == nil {
			log.Info().Msg("Broker received a nil message")
		} else {
			log.Info().Any("msg", msg).Msg("Broker received a message")
		}

	}
}
