package broker

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/morphircli/task"
	"github.com/phuslu/log"
)

type Start struct {
}

type Broker struct {
	inProcess bool
}

func NewBroker(inProcess bool) actor.Producer {
	return func() actor.Receiver {
		return &Broker{
			inProcess: inProcess,
		}
	}
}

func (b *Broker) Receive(ctx *actor.Context) {
	switch ctx.Message().(type) {
	case actor.Started:
		if b.inProcess {
			log.Info().Msg("Started in-process Broker")
		} else {
			log.Info().Msg("Broker started")
		}
	case actor.Initialized:
		log.Info().Msg("Broker initialized")
	case actor.Stopped:
		log.Info().Msg("Broker stopped")
	case Start:
		log.Info().Msg("Broker received Start message")
	case task.MakeProject:
		log.Info().Msg("Broker received MakeProject message")
	case nil:
		log.Info().Msg("Broker received nil message")
	default:
		log.Info().Msg("Broker received unknown message")
	}
}

//func New(engine *actor.Engine) *Coordinator {
//	return &Coordinator{
//		engine: engine,
//	}
//}
//
//func (c *Coordinator) Submit(ctx context.Context, task task.ITask) error {
//
//	return nil
//}
