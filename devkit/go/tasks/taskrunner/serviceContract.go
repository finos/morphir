package taskrunner

import "github.com/finos/morphir/devkit/go/tasks/task"

type TaskRunner interface {
	RunTask(task task.Task) error
}
