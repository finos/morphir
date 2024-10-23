package broker

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/internal/actorsvc"
	"github.com/finos/morphir/devkit/go/messaging/broker"
	"time"
)

// service is an implementation of the Broker service. A Broker service is responsible for dispatching
// messages to the appropriate receiver.
type service struct {
	actorsvc.ActorService
	inProcess bool
}

func (s *service) InProcess() bool {
	return s.inProcess
}

func (s *service) Publish(topic string, msg any) error {
	//TODO implement me
	panic("implement me")
}

func (s *service) Send(msg any) error {
	message := broker.SendMessage{Message: msg}
	response, err := s.ActorService.Request(message, 30*time.Second)

	if err != nil {
		return err
	}

	// If the response is an error type then return it
	if err, ok := response.(error); ok {
		return err
	}
	return nil
}

func (s *service) Request(request any, timeout time.Duration) (response any, err error) {
	return s.ActorService.Request(broker.MakeRequest{Request: request}, timeout)
}

type Config struct {
	InProcess bool
}

func New(engine *actor.Engine, config Config) broker.Broker {
	pid := engine.Spawn(NewBroker(config), "brokerActor")
	svc := &service{
		ActorService: *actorsvc.New(engine, pid),
	}
	return svc
}
