package task

type Id string
type Name string

type Task interface {
	Name() Name
	Data() any
}

type Meta struct {
	name Name
	id   *Id
}

type GenericTask[Data any] struct {
	Meta
	data Data
}

func New[Data any](name Name, data Data) *GenericTask[Data] {
	return &GenericTask[Data]{
		Meta: Meta{
			name: name,
			id:   nil,
		},
		data: data,
	}
}

func (t *GenericTask[Data]) Name() Name {
	return t.name
}

func (t *GenericTask[Data]) Data() Data {
	return t.data
}
