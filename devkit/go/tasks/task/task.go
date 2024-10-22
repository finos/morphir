package task

type TaskId string

type Task interface {
	Name() string
	Dependencies() []Task
}
