package task

type Id string

type Task interface {
	Name() string
	Dependencies() []Task
}
