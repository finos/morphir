package task

type Id string
type Name string

type ITask interface {
	Name() Name
	Data() any
}

type Task[Data any] struct {
	name Name
	id   *Id
	data Data
}

func New[Data any](name Name, data Data) *Task[Data] {
	return &Task[Data]{name: name, data: data}
}

func (t *Task[Data]) Name() Name {
	return t.name
}

func (t *Task[Data]) Data() Data {
	return t.data
}
