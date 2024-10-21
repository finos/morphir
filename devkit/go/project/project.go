package project

import (
	"encoding/json"
	"io"
)

type Project struct {
	Name              string                    `json:"name"`
	SourceDirectory   string                    `json:"sourceDirectory"`
	ExposedModules    []string                  `json:"exposedModules,omitempty"`
	LocalDependencies []string                  `json:"localDependencies,omitempty"`
	Dependencies      []string                  `json:"dependencies,omitempty"`
	Decorations       map[string]DecorationInfo `json:"decorations,omitempty"`
}

type DecorationInfo struct {
	DisplayName     string `json:"displayName"`
	IR              string `json:"ir"`
	EntryPoint      string `json:"entryPoint"`
	StorageLocation string `json:"storageLocation"`
}

func Decode(reader io.Reader) (*Project, error) {
	var project Project
	err := json.NewDecoder(reader).Decode(&project)
	if err != nil {
		return nil, err
	}
	return &project, nil
}

func Encode(writer io.Writer, project *Project) error {
	return json.NewEncoder(writer).Encode(project)
}
