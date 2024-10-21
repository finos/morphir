package workspace

type Root interface {
	underlying() root
	Path() string
}

type root string

func newRoot(path string) Root {
	return root(path)
}

type Workspace interface {
	Root() Root
}

type MorphirProjectOrWorkspace interface {
	SetName(MorphirProjectName)
	GetName() MorphirProjectName
}

func (r root) underlying() root {
	return r
}

func (r root) Path() string {
	return string(r)
}
