package session

import "github.com/finos/morphir/devkit/go/morphircli/task"

type MessageBroker interface {
	SubmitTask(task task.Task) error
}
