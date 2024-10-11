package workspaces

type MorphirProjectOrWorkspace interface {
	SetName(MorphirProjectName)
	GetName() MorphirProjectName
}
