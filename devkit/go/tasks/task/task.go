package task

type Id string
type Name string

type Task interface {
	Name() Name
	Dependencies() []Task
}

type IdentityMeta struct {
	name    Name
	id      *Id
	aliases []string
}
