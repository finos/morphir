package task

import (
	"context"
	"github.com/asynkron/protoactor-go/actor"
)

type Coordinator struct {
	sys *actor.ActorSystem
}

func (c *Coordinator) Submit(ctx context.Context, task ITask) error {

	return nil
}
