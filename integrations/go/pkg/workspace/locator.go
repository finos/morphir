package workspace

type Locator interface {
	LocateWorkspace() (work Workspace, ok bool)
}

type RootLocator interface {

	// LocateRoot locates the Root of a workspace starting from the given directory path and returns a boolean indicating success or failure.
	LocateRoot(from string) (root Root, ok bool)
}

type DefaultRootLocator struct{}

func (f DefaultRootLocator) LocateWorkspaceRoot(from string) (root Root, ok bool) {
	if from == "" {
		return nil, false
	}
	return newRoot(from), true
}
