package workspace

type ClassicMorphirManifest struct {
	Name              MorphirProjectName `json:"name"`
	SourceDirectory   SourceDirectory    `json:"sourceDirectory"`
	LocalDependencies []LocalDependency  `json:"localDependencies"`
}

type SourceDirectory string
type MorphirProjectName string
type LocalDependency string

// func (m *ClassicMorphirManifest) SetName(projectName MorphirProjectName) {
// 	m.Name = projectName
// 	return ()
// }
