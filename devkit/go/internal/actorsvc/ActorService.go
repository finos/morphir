package actorsvc

import (
	"github.com/anthdm/hollywood/actor"
	"time"
)

type ActorService struct {
	engine *actor.Engine
	pid    *actor.PID
}

func New(engine *actor.Engine, pid *actor.PID) *ActorService {
	svc := &ActorService{
		engine: engine,
		pid:    pid,
	}
	return svc
}

func (a *ActorService) Send(msg interface{}) {
	a.engine.Send(a.pid, msg)
}

func (a *ActorService) Request(msg interface{}, timeout time.Duration) (response any, err error) {
	response = a.engine.Request(a.pid, msg, timeout)
	return response, nil
}
